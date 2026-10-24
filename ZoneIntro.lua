-- Zone Intro: a cinematic banner (zone name + a line of that zone's lore) when you enter a new zone.
-- One timeline drives everything (fades, bars, drift, mist) so nothing steps between stages.

local ADDON, ns = ...

local DEFAULTS = { enabled = true, hideBlizzard = true, hideUI = true, showOnLogin = false, drift = true, show = {}, hold = 5.5, sound = 844, custom = {} }

local function DB()
    ZoneIntroDB = ZoneIntroDB or {}
    for k, v in pairs(DEFAULTS) do
        if ZoneIntroDB[k] == nil then
            ZoneIntroDB[k] = (type(v) == "table") and {} or v
        end
    end
    -- Earlier versions stored a flat list of lines; lines are now kept per zone.
    if ZoneIntroDB.custom[1] ~= nil then ZoneIntroDB.custom = {} end
    return ZoneIntroDB
end

-- Quotes ----------------------------------------------------------------------------------

local recent = {}
local lastPick = {}

local function WasRecent(q)
    for _, r in ipairs(recent) do if r == q then return true end end
    return false
end

local function Remember(q)
    table.insert(recent, q)
    if #recent > 20 then table.remove(recent, 1) end
end

-- Every line starts with a label: "Lore:" (history and facts), "Trivia:" (easter eggs, references, behind the
-- scenes) or "Note:" (tips, and fan talk that is worded as speculation). The settings panel switches each kind on or off.
local function Category(line)
    local tag = line:match("^(%a+):")
    tag = tag and tag:lower()
    if tag == "lore" or tag == "trivia" or tag == "note" then return tag end
    return "note"   -- lines you add yourself without a label count as notes
end

local function Allowed(category)
    return DB().show[category] ~= false
end

-- "The Deadmines", "Deadmines" and "the deadmines" are the same place.
local function Norm(name)
    name = name:lower():gsub("^the ", "")
    return (name:gsub("[^%w]", ""))
end

-- A few places exist in more than one era (Nagrand, Shadowmoon Valley). Lines filed under "Name" are true in
-- every era; lines filed under "Name (Draenor)" or "Name (Outland)" only play when you are on that continent.
local index
local function Index()
    if index then return index end
    index = {}
    for name, lines in pairs(ns.ZONE_QUOTES) do
        local base, era = name:match("^(.-)%s*%((.-)%)$")
        local key = Norm(base or name)
        index[key] = index[key] or { shared = {}, era = {} }
        local pool = index[key].shared
        if era then
            local e = Norm(era)
            index[key].era[e] = index[key].era[e] or {}
            pool = index[key].era[e]
        end
        for _, line in ipairs(lines) do table.insert(pool, line) end
    end
    -- Places the game names differently from the lore pages (see ns.ALIASES in Quotes.lua).
    for gameName, sources in pairs(ns.ALIASES or {}) do
        local key = Norm(gameName)
        index[key] = index[key] or { shared = {}, era = {} }
        for _, source in ipairs(sources) do
            local from = index[Norm(source)]
            if from then for _, line in ipairs(from.shared) do table.insert(index[key].shared, line) end end
        end
    end
    return index
end

-- Name of the continent you are standing on, or nil when it can't be worked out.
local function ContinentName()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    for _ = 1, 10 do
        local info = mapID and C_Map.GetMapInfo(mapID)
        if not info then return nil end
        if info.mapType == Enum.UIMapType.Continent then return info.name end
        mapID = info.parentMapID
    end
end

-- All lines written for a zone (built in and your own), before the settings filter.
local function LinesFor(zone)
    local key = Norm(zone)
    local all = {}
    local entry = Index()[key]
    if entry then
        for _, line in ipairs(entry.shared) do table.insert(all, line) end
        if next(entry.era) then
            local continent = ContinentName()
            local pool = continent and entry.era[Norm(continent)]
            if pool then for _, line in ipairs(pool) do table.insert(all, line) end end
        end
    end
    for name, lines in pairs(DB().custom) do
        if Norm(name) == key then for _, line in ipairs(lines) do table.insert(all, line) end end
    end
    return all
end

local function PickQuote(zone)
    local pool = {}
    for _, line in ipairs(LinesFor(zone)) do
        if Allowed(Category(line)) then table.insert(pool, line) end
    end
    lastPick = { zone = zone, size = #pool }
    if #pool == 0 then return nil end

    local choice
    for _ = 1, 8 do
        choice = pool[math.random(#pool)]
        if not WasRecent(choice) then break end
    end
    Remember(choice)
    return (choice:gsub("{zone}", function() return zone end))
end

-- Banner ----------------------------------------------------------------------------------

local FADE_IN, FADE_OUT = 2.2, 2.8
local BAR_FRACTION = 0.10      -- each letterbox bar's height as a share of the screen
local BAR_IN, BAR_OUT = 1.8, 2.0
local UI_FADE_OUT, UI_FADE_IN = 1.4, 2.6    -- the rest of the UI fades out first, and returns as the banner leaves

local savedUIAlpha        -- UIParent's alpha before we touched it; non-nil while the UI is faded

local frame, band, driver
local barTop, barBottom
local mist = {}
local startTime, totalTime

local function Clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
local function Smooth(x) x = Clamp01(x) return x * x * (3 - 2 * x) end   -- ease in and out

local function SetFontSafe(fs, path, size, flags, fallbackObject)
    if not fs:SetFont(path, size, flags) then fs:SetFontObject(fallbackObject) end
end

-- Lets a texture move by fractions of a pixel instead of jumping from pixel to pixel.
local function NoSnap(tex)
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    return tex
end

local function EdgeGradient(parent, p1, p2, orientation, minColor, maxColor, size, isHeight)
    local t = NoSnap(parent:CreateTexture(nil, "BACKGROUND"))
    t:SetColorTexture(1, 1, 1, 1)
    t:SetPoint(p1); t:SetPoint(p2)
    if isHeight then t:SetHeight(size) else t:SetWidth(size) end
    t:SetGradient(orientation, minColor, maxColor)
end

-- Mist: a soft cloud built from thin strips. Each strip fades out at its left and right ends, and the
-- strips' strength follows a bell curve from top to bottom, so no hard edge is visible anywhere.
local MIST_STRIPS, MIST_HEIGHT = 14, 120

local function MakeMist(y, amplitude, period, phase, strength)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(1100, MIST_HEIGHT)
    local stripHeight = MIST_HEIGHT / MIST_STRIPS
    for i = 0, MIST_STRIPS - 1 do
        local bell = math.sin(math.pi * (i + 0.5) / MIST_STRIPS)
        local a = strength * bell * bell
        local top = -i * stripHeight

        local left = NoSnap(holder:CreateTexture(nil, "BACKGROUND", nil, 1))
        left:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, top)
        left:SetPoint("BOTTOMRIGHT", holder, "TOP", 0, top - stripHeight)
        left:SetColorTexture(1, 1, 1, 1)
        left:SetGradient("HORIZONTAL", CreateColor(0.8, 0.85, 0.95, 0), CreateColor(0.8, 0.85, 0.95, a))

        local right = NoSnap(holder:CreateTexture(nil, "BACKGROUND", nil, 1))
        right:SetPoint("TOPLEFT", holder, "TOP", 0, top)
        right:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, top - stripHeight)
        right:SetColorTexture(1, 1, 1, 1)
        right:SetGradient("HORIZONTAL", CreateColor(0.8, 0.85, 0.95, a), CreateColor(0.8, 0.85, 0.95, 0))
    end
    table.insert(mist, { frame = holder, y = y, amplitude = amplitude, period = period, phase = phase })
end

-- Opening any of these means you want to use the UI now, so the fade gives way immediately.
local PANELS = {
    "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "WorldMapFrame", "GameMenuFrame", "SettingsPanel",
    "CollectionsJournal", "AchievementFrame", "ProfessionsFrame", "EncounterJournal", "FriendsFrame", "PVEFrame",
    "MerchantFrame", "GossipFrame", "QuestFrame", "BankFrame", "MailFrame", "AuctionHouseFrame", "TradeFrame",
    "ContainerFrameCombinedBags", "ContainerFrame1", "HousingDashboardFrame", "CommunitiesFrame",
}
local function PanelOpen()
    for _, name in ipairs(PANELS) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end

local aborting, abortStart, abortUI, abortScene, abortBars
local lastPanelCheck = 0

local function RestoreUI()
    if savedUIAlpha then
        UIParent:SetAlpha(savedUIAlpha)
        savedUIAlpha = nil
    end
end

local function Build()
    if frame then return end

    -- Parented to WorldFrame, not UIParent, so it stays visible while the rest of the UI fades.
    -- WorldFrame isn't scaled by your UI scale, so match it to keep sizes the same.
    frame = CreateFrame("Frame", "ZoneIntroFrame", WorldFrame)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetScale(UIParent:GetEffectiveScale())
    frame:SetAllPoints(UIParent)
    frame:EnableMouse(false)
    frame:SetAlpha(0)
    frame:Hide()

    -- Soft vignette at the screen edges. There is no dark panel behind the text.
    local edge = CreateColor(0, 0, 0, 0.45)
    local clear = CreateColor(0, 0, 0, 0)
    EdgeGradient(frame, "TOPLEFT", "BOTTOMLEFT", "HORIZONTAL", edge, clear, 380, false)
    EdgeGradient(frame, "TOPRIGHT", "BOTTOMRIGHT", "HORIZONTAL", clear, edge, 380, false)

    -- Letterbox bars; their height is animated by the timeline.
    barTop = NoSnap(frame:CreateTexture(nil, "BACKGROUND", nil, 3))
    barTop:SetColorTexture(0, 0, 0, 0.95)
    barTop:SetPoint("TOPLEFT"); barTop:SetPoint("TOPRIGHT")
    barTop:SetHeight(1)
    barBottom = NoSnap(frame:CreateTexture(nil, "BACKGROUND", nil, 3))
    barBottom:SetColorTexture(0, 0, 0, 0.95)
    barBottom:SetPoint("BOTTOMLEFT"); barBottom:SetPoint("BOTTOMRIGHT")
    barBottom:SetHeight(1)

    -- Text container. Drifts slowly sideways; it is never scaled.
    band = CreateFrame("Frame", nil, frame)
    band:SetSize(900, 200)

    band.title = band:CreateFontString(nil, "OVERLAY")
    SetFontSafe(band.title, "Fonts\\MORPHEUS.TTF", 52, "OUTLINE", GameFontNormalHuge)
    band.title:SetPoint("CENTER", band, "CENTER", 0, 30)
    band.title:SetTextColor(1, 0.94, 0.78)
    band.title:SetShadowColor(0, 0, 0, 1)
    band.title:SetShadowOffset(3, -3)

    band.lineL = NoSnap(band:CreateTexture(nil, "ARTWORK"))
    band.lineL:SetSize(200, 2)
    band.lineL:SetPoint("TOPRIGHT", band.title, "BOTTOM", 0, -12)
    band.lineL:SetColorTexture(1, 1, 1, 1)
    band.lineL:SetGradient("HORIZONTAL", CreateColor(0.85, 0.68, 0.25, 0), CreateColor(0.85, 0.68, 0.25, 0.9))
    band.lineR = NoSnap(band:CreateTexture(nil, "ARTWORK"))
    band.lineR:SetSize(200, 2)
    band.lineR:SetPoint("TOPLEFT", band.title, "BOTTOM", 0, -12)
    band.lineR:SetColorTexture(1, 1, 1, 1)
    band.lineR:SetGradient("HORIZONTAL", CreateColor(0.85, 0.68, 0.25, 0.9), CreateColor(0.85, 0.68, 0.25, 0))

    band.quote = band:CreateFontString(nil, "OVERLAY")
    SetFontSafe(band.quote, "Fonts\\FRIZQT__.TTF", 19, "OUTLINE", GameFontNormalLarge)
    band.quote:SetPoint("TOP", band.title, "BOTTOM", 0, -30)
    band.quote:SetWidth(820)
    band.quote:SetJustifyH("CENTER")
    band.quote:SetTextColor(0.9, 0.88, 0.95)
    band.quote:SetShadowColor(0, 0, 0, 1)
    band.quote:SetShadowOffset(2, -2)

    -- Mist: streaks that sway slowly across the screen.
    MakeMist(70, 320, 15, 0.0, 0.10)
    MakeMist(20, -360, 18, 1.6, 0.12)
    MakeMist(-30, 300, 13, 3.1, 0.10)
    MakeMist(-80, -340, 20, 4.4, 0.11)

    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", function()
        local now = GetTime()
        local t = now - startTime

        -- Opening a panel (character, map, bags...) cancels the fade quickly, so you never have to wait.
        if not aborting and savedUIAlpha and now - lastPanelCheck > 0.1 then
            lastPanelCheck = now
            if PanelOpen() then
                aborting = true
                abortStart = now
                abortUI = UIParent:GetAlpha()
                abortScene = frame:GetAlpha()
                abortBars = barTop:GetHeight()
            end
        end

        if aborting then
            local p = Smooth((now - abortStart) / 0.4)
            if savedUIAlpha then UIParent:SetAlpha(abortUI + (savedUIAlpha - abortUI) * p) end
            frame:SetAlpha(abortScene * (1 - p))
            local h = math.max(1, abortBars * (1 - p))
            barTop:SetHeight(h)
            barBottom:SetHeight(h)
            if p >= 1 then
                aborting = false
                driver:Hide()
                frame:SetAlpha(0)
                frame:Hide()
                RestoreUI()
            end
            return
        end

        if t >= totalTime then
            driver:Hide()
            frame:SetAlpha(0)
            frame:Hide()
            RestoreUI()
            return
        end

        -- Fade the rest of the UI away, then bring it back as the banner leaves.
        if savedUIAlpha then
            local away = Smooth(t / UI_FADE_OUT) * (1 - Smooth((t - (totalTime - UI_FADE_IN)) / UI_FADE_IN))
            UIParent:SetAlpha(savedUIAlpha * (1 - away))
        end

        local scene = Smooth(t / FADE_IN) * (1 - Smooth((t - (FADE_IN + DB().hold)) / FADE_OUT))
        frame:SetAlpha(scene)

        -- Bars slide in first, and slide away at the end.
        local bars = Smooth(t / BAR_IN) * (1 - Smooth((t - (totalTime - BAR_OUT)) / BAR_OUT))
        local barHeight = math.max(1, UIParent:GetHeight() * BAR_FRACTION * bars)
        barTop:SetHeight(barHeight)
        barBottom:SetHeight(barHeight)

        -- Title emerges from the mist, then the quote.
        band.title:SetAlpha(Smooth((t - 0.6) / 1.8))
        local hasQuote = band.quote:GetText() and band.quote:GetText() ~= ""
        band.quote:SetAlpha(hasQuote and Smooth((t - 2.0) / 1.8) or 0)
        band.lineL:SetAlpha(hasQuote and Smooth((t - 1.6) / 1.4) or 0)
        band.lineR:SetAlpha(hasQuote and Smooth((t - 1.6) / 1.4) or 0)

        -- A gentle sideways drift. Text is never scaled: scaling is what made the old pan jump.
        local progress = t / totalTime
        local cx = DB().drift and (30 * (Smooth(progress) - 0.5)) or 0
        local cy = -(UIParent:GetHeight() * 0.14 + 110)
        band:ClearAllPoints()
        band:SetPoint("CENTER", frame, "TOP", cx, cy)

        for _, m in ipairs(mist) do
            local x = m.amplitude * math.sin((t / m.period) * 2 * math.pi + m.phase)
            m.frame:ClearAllPoints()
            m.frame:SetPoint("CENTER", frame, "TOP", x, cy + m.y)
        end
    end)
end

local function PlayChime()
    local sound = DB().sound
    if not sound then return end
    -- Tied to the Sound Effects setting in the Audio options.
    if GetCVar("Sound_EnableSFX") ~= "1" then return end
    PlaySound(sound, "SFX")
end

local function Show(zone, quote)
    Build()
    band.title:SetText(zone)
    band.quote:SetText(quote or PickQuote(zone) or "")
    totalTime = FADE_IN + DB().hold + FADE_OUT
    startTime = GetTime()
    frame:SetScale(UIParent:GetEffectiveScale())
    frame:SetAlpha(0)
    frame:Show()
    driver:Show()
    PlayChime()

    aborting = false
    if DB().hideUI and not InCombatLockdown() and UIParent:IsShown() and not PanelOpen() then
        if not savedUIAlpha then savedUIAlpha = UIParent:GetAlpha() end
        -- Failsafe: whatever happens, the UI is back shortly after the banner should be gone.
        C_Timer.After(totalTime + 3, function()
            if GetTime() - startTime >= totalTime then RestoreUI() end
        end)
    else
        RestoreUI()
    end
end

-- Triggers ------------------------------------------------------------------------------------

local lastZone
local lastShown = {}
local SAME_ZONE_COOLDOWN = 90   -- the same zone won't replay within this many seconds
local GLOBAL_COOLDOWN = 25      -- no two banners closer together than this
local STABLE_FOR = 2.5          -- you must stay in a zone this long before its banner plays
local lastBanner = -1000
local pendingId = 0

local function CurrentZone()
    local zone = GetRealZoneText()
    if not zone or zone == "" then zone = GetZoneText() end
    if not zone or zone == "" then return nil end
    return zone
end

local function Check(force)
    if not DB().enabled then return end
    local zone = CurrentZone()
    if not zone then return end
    if zone == lastZone and not force then return end
    lastZone = zone

    local now = GetTime()
    if not force then
        if lastShown[zone] and now - lastShown[zone] < SAME_ZONE_COOLDOWN then return end
        if now - lastBanner < GLOBAL_COOLDOWN then return end
    end
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return end
    lastShown[zone] = now
    lastBanner = now
    Show(zone)
end

-- Zone events go through here. Only the last change in a quick run of them is acted on, so flying across
-- several zones plays one banner for where you end up, not one per border.
local function ScheduleCheck(delay)
    pendingId = pendingId + 1
    local id = pendingId
    C_Timer.After(delay, function()
        if id ~= pendingId then return end
        Check(false)
    end)
end

local BuildSettings   -- defined with the settings panel below

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_LEAVING_WORLD")

local hooked = false
local function HookBlizzard()
    if hooked or not ZoneTextFrame then return end
    hooked = true
    hooksecurefunc(ZoneTextFrame, "Show", function(self)
        if DB().enabled and DB().hideBlizzard then self:Hide() end
    end)
end

events:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
        RestoreUI()   -- never leave the UI hidden once a fight starts or a loading screen begins
    elseif event == "PLAYER_LOGIN" then
        pcall(HookBlizzard)
        pcall(BuildSettings)
    elseif event == "PLAYER_ENTERING_WORLD" and (isReloadingUi or (isInitialLogin and not DB().showOnLogin)) then
        -- A /reload or the first login shouldn't play a banner; just remember where we are.
        lastZone = GetRealZoneText()
    else
        ScheduleCheck(STABLE_FOR)
    end
end)

-- Settings panel -------------------------------------------------------------------------------

local Say   -- defined with the commands below

local settingsCategory
function BuildSettings()
    if settingsCategory or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame", "ZoneIntroSettings", UIParent)
    panel.name = "Zone Intro"

    local title = panel:CreateFontString(nil, "ARTWORK")
    title:SetFont(STANDARD_TEXT_FONT, 16)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Zone Intro")

    local intro = panel:CreateFontString(nil, "ARTWORK")
    intro:SetFont(STANDARD_TEXT_FONT, 13)
    intro:SetTextColor(0.8, 0.8, 0.8)
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetText("Choose which kinds of line the banner can show under the zone name.")

    local last = intro
    local function Check(label, getter, setter, gap)
        local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, gap or -10)
        box.Text:SetFont(STANDARD_TEXT_FONT, 14)
        box.Text:SetTextColor(1, 0.82, 0)
        box.Text:SetText(label)
        box:SetChecked(getter())
        box:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
        last = box
        return box
    end

    local function ShowKind(key) return function() return DB().show[key] ~= false end end
    local function SetKind(key) return function(v) DB().show[key] = v end end
    Check(" Lore: history and facts about the place", ShowKind("lore"), SetKind("lore"), -18)
    Check(" Trivia: easter eggs, references, behind the scenes", ShowKind("trivia"), SetKind("trivia"))
    Check(" Notes: tips, and fan talk worded as speculation", ShowKind("note"), SetKind("note"))
    Check(" Show a banner when entering zones", function() return DB().enabled end, function(v) DB().enabled = v end, -26)
    Check(" Fade the rest of the UI during the banner", function() return DB().hideUI end, function(v) DB().hideUI = v; if not v then RestoreUI() end end)
    Check(" Also show it on first login", function() return DB().showOnLogin end, function(v) DB().showOnLogin = v end)
    Check(" Slow sideways drift of the text", function() return DB().drift end, function(v) DB().drift = v end)

    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "Zone Intro")
    Settings.RegisterAddOnCategory(settingsCategory)
end

local function OpenSettings()
    BuildSettings()
    if settingsCategory then
        local ok = pcall(Settings.OpenToCategory, settingsCategory:GetID())
        if not ok then Settings.OpenToCategory(settingsCategory.ID) end
    else
        Say("the settings panel isn't available on this client; use /zoneintro lore, trivia or notes instead.")
    end
end

-- Commands ------------------------------------------------------------------------------------

function Say(text) print("|cffffd100Zone Intro:|r " .. text) end

local function Report(zone, simulated)
    local db = DB()
    Say("--- zone test " .. (simulated and "(made-up zone name)" or "(as if you just entered your current zone)") .. " ---")
    Say("zone: '" .. zone .. "'   (GetRealZoneText='" .. tostring(GetRealZoneText()) .. "', GetZoneText='" .. tostring(GetZoneText()) .. "')")
    local all = LinesFor(zone)
    local counts = { lore = 0, trivia = 0, note = 0 }
    for _, line in ipairs(all) do local c = Category(line); counts[c] = counts[c] + 1 end
    if #all == 0 then
        Say("no lines for this zone yet, so only the title is shown. Add one: /zoneintro add " .. zone .. " | your line")
    else
        Say(string.format("lines for this zone: %d lore, %d trivia, %d notes (%s, %s, %s)", counts.lore, counts.trivia, counts.note,
            Allowed("lore") and "lore on" or "lore off", Allowed("trivia") and "trivia on" or "trivia off", Allowed("note") and "notes on" or "notes off"))
    end
    Say("showOnLogin=" .. tostring(db.showOnLogin) .. "  drift=" .. tostring(db.drift) .. "  cooldowns: " .. GLOBAL_COOLDOWN .. "s between banners, " .. SAME_ZONE_COOLDOWN .. "s for the same zone")
    Say("enabled=" .. tostring(db.enabled) .. "  hideUI=" .. tostring(db.hideUI) .. "  hideBlizzard=" .. tostring(db.hideBlizzard)
        .. "  hold=" .. tostring(db.hold) .. "s  sound=" .. tostring(db.sound))
    Say("Sound Effects setting: " .. (GetCVar("Sound_EnableSFX") == "1" and "on (the chime can play)" or "off (the chime is muted)"))
    Say("Blizzard zone text frame found: " .. tostring(ZoneTextFrame ~= nil) .. "  hooked: " .. tostring(hooked))
    local since = lastShown[zone] and (GetTime() - lastShown[zone]) or nil
    Say("last real banner for this zone: " .. (since and string.format("%.0fs ago (cooldown %ds, bypassed by this test)", since, SAME_ZONE_COOLDOWN) or "never"))
end

local function CountQuotes()
    local zones, lines = 0, 0
    local byKind = { lore = 0, trivia = 0, note = 0 }
    for _, pool in pairs(ns.ZONE_QUOTES) do
        zones = zones + 1
        lines = lines + #pool
        for _, line in ipairs(pool) do local c = Category(line); byKind[c] = byKind[c] + 1 end
    end
    local own = 0
    for _, pool in pairs(DB().custom) do own = own + #pool end
    return zones, lines, own, byKind
end

SLASH_ZONEINTRO1 = "/zoneintro"
SlashCmdList["ZONEINTRO"] = function(msg)
    local db = DB()
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "test" then
        if rest ~= "" then
            Show(rest)
            Report(rest, true)
        else
            -- Same path as walking into a zone: ignores the cooldown, respects everything else.
            local wasEnabled = db.enabled
            db.enabled = true
            Check(true)
            db.enabled = wasEnabled
            Report(GetRealZoneText() or "?", false)
            if not wasEnabled then Say("note: the addon is switched off, so a real entry would show nothing.") end
        end
    elseif cmd == "on" then
        db.enabled = true; Say("on")
    elseif cmd == "off" then
        db.enabled = false; RestoreUI(); Say("off")
    elseif cmd == "ui" then
        db.hideUI = not db.hideUI
        if not db.hideUI then RestoreUI() end
        Say("fading the rest of the UI during the banner: " .. (db.hideUI and "on" or "off"))
    elseif cmd == "restore" then
        RestoreUI(); UIParent:SetAlpha(1); Say("UI restored")
    elseif cmd == "blizz" then
        db.hideBlizzard = not db.hideBlizzard
        Say("Blizzard's zone text is " .. (db.hideBlizzard and "hidden (takes effect on your next zone change)" or "shown again"))
    elseif cmd == "hold" then
        local seconds = tonumber(rest)
        if seconds and seconds >= 1 and seconds <= 20 then
            db.hold = seconds; Say("banner holds for " .. seconds .. "s")
        else
            Say("usage: /zoneintro hold <1-20 seconds>")
        end
    elseif cmd == "sound" then
        if rest == "off" then
            db.sound = false; Say("sound off")
        elseif tonumber(rest) then
            db.sound = tonumber(rest); Say("sound set to " .. db.sound .. ". Playing it now (needs Sound Effects on).")
            PlayChime()
        elseif rest == "" then
            Say("current sound: " .. tostring(db.sound) .. ". /zoneintro sound <soundKitID> to change, off to mute.")
            PlayChime()
        else
            Say("usage: /zoneintro sound <soundKitID|off>")
        end
    elseif cmd == "add" then
        local zone, line = rest:match("^(.-)%s*|%s*(.+)$")
        if zone and zone ~= "" and line then
            db.custom[zone] = db.custom[zone] or {}
            table.insert(db.custom[zone], line)
            Say("added a line for " .. zone .. ". You now have " .. #db.custom[zone] .. " of your own there.")
        else
            Say("usage: /zoneintro add <exact zone name> | <your line>")
        end
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        OpenSettings()
    elseif cmd == "lore" or cmd == "trivia" or cmd == "notes" then
        local key = (cmd == "notes") and "note" or cmd
        db.show[key] = not (db.show[key] ~= false)
        Say(cmd .. ": " .. ((db.show[key] ~= false) and "on" or "off"))
    elseif cmd == "login" then
        db.showOnLogin = not db.showOnLogin
        Say("banner when you first log in: " .. (db.showOnLogin and "on" or "off"))
    elseif cmd == "drift" then
        db.drift = not db.drift
        Say("sideways drift: " .. (db.drift and "on" or "off") .. " (turn it off if you want the text perfectly still)")
    elseif cmd == "count" then
        local zones, lines, own, kinds = CountQuotes()
        Say(lines .. " built-in lines across " .. zones .. " places (" .. kinds.lore .. " lore, " .. kinds.trivia .. " trivia, " .. kinds.note .. " notes), plus " .. own .. " of your own.")
    else
        Say("/zoneintro settings  |  test [made-up zone]  |  lore  |  trivia  |  notes  |  on  |  off  |  ui  |  login  |  drift  |  restore  |  blizz  |  hold <sec>  |  sound <id|off>  |  add <zone> | <line>  |  count")
    end
end
