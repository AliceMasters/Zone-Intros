# Zone Intro

A cinematic banner for World of Warcraft: when you enter a zone, the letterbox bars slide in, the rest of the UI fades away, and the zone's name appears with one short line about the place.

Every line starts with a plain label, so you can choose what you want to read:

- **Lore:** history, people and facts about the place.
- **Trivia:** easter eggs, references, real-world inspirations and development trivia.
- **Note:** practical tips, secrets, rare spawns, travel hints, and fan speculation (always worded as speculation).

No colours, no icons. The text stays in the same quiet tone throughout.

## What is in it

- About **4,800 lines across 499 places**: every zone, city, dungeon, raid, battleground, arena, scenario, delve and island expedition on the master list, from Classic through Midnight.
- Most places have 10 or more lines. Places with very little verified material (cut content, small scenarios) have fewer. Nothing is padded.
- Places that exist on two continents (Nagrand, Shadowmoon Valley) show lines for the continent you are standing on.

## Settings

`/zoneintro settings` opens the panel (also under AddOns in the game options):

- Show Lore, Trivia and Notes independently.
- Show the banner at all.
- Fade the rest of the UI during the banner.
- Also show it on first login.
- Slow sideways drift of the text.

## Commands

| Command | What it does |
| --- | --- |
| `/zoneintro settings` | Open the settings panel |
| `/zoneintro test [zone]` | Play the banner for the current zone, or a zone you name |
| `/zoneintro lore` / `trivia` / `notes` | Switch that kind of line on or off |
| `/zoneintro on` / `off` | Turn the banner on or off |
| `/zoneintro ui` | Toggle fading the rest of the UI |
| `/zoneintro login` | Toggle the banner on first login |
| `/zoneintro drift` | Toggle the sideways drift |
| `/zoneintro restore` | Bring the UI back if it is ever left faded |
| `/zoneintro blizz` | Toggle hiding Blizzard's own zone text |
| `/zoneintro add Zone \| your line` | Add your own line for a zone |
| `/zoneintro count` | Show how many lines are built in |

## Behaviour you can rely on

- Opening any panel (character, map, bags and so on) while the UI is faded ends the fade quickly, so you are never kept waiting.
- Rapid zone changes only play one banner, for where you end up.
- No banner on `/reload` or the first login, unless you turn it on.
- The banner is skipped in combat, in pet battles, and when you are already looking at a panel.

## Sources and accuracy

Lines were written from the pages of warcraft.wiki.gg, one place at a time, and kept short. Anything that is fan theory is labelled as speculation. Content the wiki marks as non-canon was left out, and so were hotfix details and level ranges, which go stale. Some Midnight content comes from the wiki as it stands today and may change.

If you find a line that is wrong, open an issue with the zone name and the line.

## Install

Copy the `ZoneIntro` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
