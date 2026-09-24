<p align="center"><img src="media/logo.png" alt="Alts Forever logo" width="200"></p>

# Alts Forever

By **Kadmai**.

A World of Warcraft: Forever addon (interface 16001) that adds a total and a per-character breakdown of an item to its tooltip:

```
Total                                  48
Aldric                  [bag] 2         2
Big          [bag] 30 · [mail] 10      40
Mid-Other              [bank] 5         5
```

Locations are shown as icons: Red Linen Bag (bags), banker (bank), mailbox (mail) and white shirt (wearing).

The current character always comes first. Other characters are sorted by count.

Hovering the money at the bottom of your bags lists each character's gold and the total, laid out the same way.

Type `/af` to open the **overview**: every character with level and XP, rested XP (including what they've built up since logging out), gold, main professions, zone, time played and when you last played them, with total gold and total time played at the bottom. Hover a row for details such as rested XP until full, hearthstone location and item level. **Click a row** to see that character's gear, laid out like the character panel: hover any item for its tooltip, shift-click to link it in chat. Nearly broken items are tinted red and the lowest durability is shown.

**Mail expiry:** a few seconds after you log in, Alts Forever warns in chat if any character has mail with items or gold expiring within 3 days, and says whether it'll be returned to the sender or deleted. The overview's Mail column shows how long each character has; `/af mail` lists them all.

Hovering a recipe (pattern, schematic, formula...) lists your characters who have that profession: **Known**, **Can learn**, **Needs 120 (107)** (required skill, their skill), or **Not scanned**. Open each profession window once on each character so Alts Forever knows which recipes they've learned.

**Can craft:** hovering any item that one of your characters knows how to make adds a "Can craft" section listing them one per line (the current character first). This also comes from opening each profession window once.

## Status

Bags (including the keyring and reagent bag), bank tabs, mail (including items you mail to your alts), equipped items and equipped bags.
The bank and inbox are read when you open them; until then that character shows no bank or mail counts.

## Install

1. Link or copy this folder to `<WoW Forever>\Interface\AddOns\AltsForever`. The folder in `AddOns` must be named `AltsForever`.
2. **Forever beta only:** the client writes saved data on logout but never loads it back, so Alts Forever would forget your other characters every launch. Run this once to work around it:
   ```
   .\tools\link-saved-data.ps1 -WowDir "C:\Program Files (x86)\World of Warcraft\_classic_beta_"
   ```
   It links `SavedData` to your account's `WTF\Account\<account>\SavedVariables` folder. The `.toc` lists `SavedData\AltsForever.lua`, so the game runs the saved file as ordinary addon code. Once Blizzard fixes the bug, remove that line from both `.toc` files.

   If no saved data loads, Alts Forever says so in chat a few seconds after login, explains the bug and points to `AltsForever.lua.bak`, the game's copy of the previous save.

## Commands

| Command | What it does |
|---|---|
| `/af` | Open or close the overview window |
| `/af mail` | List every character's soonest mail expiry |
| `/af restcheck` | Turn the rested XP check message on or off |
| `/af list` | List stored characters |
| `/af delete Name-Realm` | Forget a character |
| `/af realm` | Toggle between all realms and this realm only |
| `/af mem` | Show the addon's memory use |

`/altsforever` and the old `/it` also work.

## Tests

The tests run the addon outside the game against a small fake of the WoW API (`tests/wow.lua`). They need Lua 5.1 (the version WoW uses):

```
luajit tests/run.lua
```

## Design notes

- Stores only `itemID -> count` per location per character. It doesn't store slot positions or item links.
- Scans only happen on events. `BAG_UPDATE_DELAYED` groups a batch of changes into one scan, and only when a carried bag changed. There are no OnUpdate handlers.
- Scans refill the existing tables and read stacks through one reused `ItemLocation`, so a scan allocates nothing.
- Other characters' tooltip lines are built once per item and cached, up to 500 items. The current character's line is recomputed only when their data changes.

## Development

Run the tests with `luajit tests/run.lua` from the project root (LuaJIT is Lua 5.1, the same as WoW). `tests/wow.lua` fakes just enough of the WoW API to load the addon outside the game. Run `tools/fetch-reference.ps1` to download the API references into `reference/`.
