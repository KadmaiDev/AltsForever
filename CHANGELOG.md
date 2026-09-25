## Unreleased

- **Click instead of typing:** Alts Forever is in the minimap's addon menu (click: open the overview, right-click: options). The overview has an options button, and right-clicking a character there lets you forget them (with a confirmation). There's also an Alts Forever page under Options → AddOns with the skill-up setting.

## Alts Forever 0.3.0

- **Skill-ups across your alts.** Alts Forever now knows the level at which each recipe your characters know stops giving skill-ups (read from the game when a profession window opens):
  - **Can craft:** characters who'd still get a skill-up from making the item are marked "· skill-ups to 115".
  - **Materials:** hovering a material adds a "Skill-ups" section listing the recipes your characters can still skill up with it, e.g. "Heavy Linen Bandage   Tarnia · to 115". You come first, then your other characters, each with their 2 recipes that have the most skill-ups left, up to 6 lines.
  - **Overview:** a character's row tooltip counts each profession's recipes that still give skill-ups, or says "train to skill up" when they're at their rank's maximum (e.g. 75/75). Characters at their maximum aren't listed for skill-ups until they train.
  - Open each profession window once per character to fill this in. `/af skillups` turns it all off.
- **Fixed:** recipes could be saved under the wrong profession (the game's recipe list sometimes includes all of a character's professions). Recipes are now checked, and lists saved by earlier versions are repaired automatically when a profession window is opened; nothing is reset.
- **Faster:** the "Can craft" lines are looked up when you hover an item instead of kept in memory for every craftable item.
- `/af delete` now also forgets recipes no remaining character knows.
- **Removed** the old `/it` command (use `/af`).

## Alts Forever 0.2.2

- **Fixed:** since WoW Forever build 70009, characters were saved under their first name only (e.g. "Mira" instead of "Mira Dawnfield"), because the game now gives the surname separately. Alts Forever now reads the full name, renames first-name entries and merges any duplicates.

## Alts Forever 0.2.1

- **Saved data works normally now.** Blizzard fixed the WoW Forever bug that stopped addons' saved data from loading (build 1.60.1.70009), so the built-in workaround is gone. If you made the `SavedData` folder link for Alts Forever, you no longer need it.
- **Fixed:** since build 70009 a character could be saved twice, once under their first name only (e.g. "Mira" and "Mira Dawnfield"), because the game briefly reports only the first name after login. Alts Forever now waits for the full name, and merges any duplicates it already saved.
- **Fixed:** "Total time played" no longer shows up in chat when you log in. Typing `/played` still works as usual.
- **Removed:** the "No saved data was loaded" chat message, which only explained the Blizzard bug.

## Alts Forever 0.2.0 (first release, beta)

Keeps track of all your characters on WoW Forever.

- **Item counts in tooltips:** a total and a per-character breakdown (bags, bank, mail, equipped) for every item, including the keyring and reagent bag.
- **Gold:** hover the money in your bags to see every character's gold and the total.
- **Overview window (`/af`):** level and XP, rested XP (including what's built up while logged out), gold, main professions, mail expiry, zone, time played and when you last played each character. Click a character to see their gear.
- **Recipes:** recipe tooltips show which characters know the recipe, can learn it or need more skill.
- **Can craft:** item tooltips list which of your characters can make the item.
- **Mail expiry:** a warning at login when mail with items or gold is about to expire.
- **Mail to alts:** items and gold you mail to your own characters are counted straight away.

**WoW Forever beta:** the game currently saves addon data but doesn't load it back. Alts Forever tells you in chat when this happens; see the description for the workaround.
