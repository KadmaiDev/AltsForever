## Alts Forever 0.17.0 (not yet released)

- **Item names for use outside the game** (off by default; options, or `/af itemnames`): for players who read Alts Forever's saved file with their own tools. Bags, bank and mail store only item IDs and counts there; with this on, the name and quality of every item your characters have are saved too when you log out. It adds nothing in the game and uses a little more memory, so leave it off unless you read the file. Thanks to the player who asked for this!
- **Ready for the live game:** the first time you log in on a live realm, Alts Forever offers to forget your characters from the beta, who don't carry over (your settings are kept). Choose Keep and you can do it later with `/af forgetbeta`. A new character with the same name as one of your beta characters starts fresh instead of inheriting the beta one's bags, bank and gold.

## Alts Forever 0.16.0

- **Export your characters** (the note button in the overview's title bar, or `/af export`): every character's level, XP, rested, Well Rested, Legacy points, gold, professions, mail expiry, zone, time played and when you last played them, ready to copy with Ctrl+C, grouped by ruleset and faction like the overview. Pick the format: **Spreadsheet** (columns that paste straight into Excel or Google Sheets, with gold, percentages and dates as numbers), **Text** (readable lines for notes or chat) or **Markdown table** (for Notion, Obsidian and the like). (A player's request.)
- The overview's "Online" (your own row, under Last seen) is now in your game's language.

## Alts Forever 0.15.0

- **Search your characters** (`/afs`, the magnifier in the overview, Search... in the options menu, or a key binding): type part of a name to find every item your characters have or can craft, with how many, who has them and who can make it. Enter opens that character's bags or bank with the item lit up, and the search stays open beside it for the next one; a worn item opens their gear on the search's other side (it stays lit as you switch character or bags and bank; the arrows at the bottom step through everyone who has it, the character list shows how many each has, and "Showing: ..." clears it). Right-click a result to choose whose bags or bank; Shift+Enter links it. The bags window has a search button in its title bar too, and a character menu beside the search box narrows it to any characters you tick, or all of them. With the bags window open the search starts on that character, opened beside it, with the selected item lit as you go (Enter keeps it lit while the search is open, and closing the search shows every slot again; the bags window keeps one height meanwhile). The search remembers what you last typed. `@owned` (has it) or `@craft` (can make it) narrows it. `/af find` opens it too, instead of listing items in chat.
- **Bags window with EllesmereUI:** its slots, and the gear panel's and craft list's, now look like EllesmereUI's bags and character sheet: square icons with a thin border in the item's quality colour, faded empty slots, outlined counts and light grey section headings, and with EllesmereUI's bags in use the same background as theirs.
- **Options page tidied:** two columns with headings (tooltips and their icons on the left; extras, minimap button and window size on the right), so nothing runs off the bottom.
- **Shorter options menu:** right-clicking the minimap button (or the overview's cog) now offers Open overview, Bags and bank, Show other rulesets and factions and Settings…; the settings you only set once are on the Options page. Memory use is still `/af mem`.
- **Controller:** the character sheet's anvils work with the Gamepad UI (A opens the list with focus in it, B closes it), and the window size has - and + buttons.

## Alts Forever 0.14.0

- **Upgrades shown as chevrons:** instead of a percentage, an upgrade now shows one green chevron for minor, two stacked for decent and three for major. It's judged against everything the character wears, not just the item it replaces, so +1 Agility over a cloak with only armour no longer shows as +583%.
- **Craftable upgrades on the character sheet:** a small anvil appears beside a gear slot when you or one of your alts can craft an upgrade for it that you can wear now and that binds when equipped. Armour is only the heaviest type you wear (no leather for a warrior), and only characters who can mail you count. The anvil carries the best one's chevrons, so you can judge each slot at a glance. Hover it to see the best few and who makes them; click it to see them all (shift-click one to link it). Turn them off with **Show craftable upgrades on the character sheet** in the options, or `/af anvils`.
- **Window size** (options, or `/af scale 150`): make Alts Forever's windows bigger or smaller, from 50% to 300%, on top of the game's UI scale. Handy if you play at a small UI scale. With EllesmereUI, the windows follow its Window Scale until you choose a size of your own. Thanks to the player who asked for this!
- **Weapons compared like for like:** a weapon is only judged against the kind you wield now. With a sword and shield (or two one-handers) you see one-handed upgrades, not two-handers weighed against both; with a two-hander, only two-handers.

## Alts Forever 0.13.0

- **Show item counts** (options, or `/af counts`): turn off the item counts in tooltips if another addon, such as Baganator or Bagnon, already shows them, so you don't see two lists. Can craft, skill-ups, upgrades and Waylaid Crates stay.
- **Data broker launcher:** with a data broker display such as Bazooka, Titan Panel or ChocolateBar, Alts Forever shows up there: click for the overview, right-click for options. Hide the minimap button and it stays. Thanks to the player who asked for this!
- **Upgrades at the profession trainer:** hovering a recipe in a trainer's list now shows which of your characters the item it makes would be an upgrade for, like recipe items already did. If the item binds on pickup, only you are listed.

## Alts Forever 0.12.0

- **Rulesets and factions kept apart:** Normal, PvP, Roleplaying and Hardcore each have their own auction house and mail, and mail never crosses factions, so those characters can't trade with yours. Alts Forever now notes each character's ruleset when you log in on them. Thanks to the player who asked for this!
  - The overview groups your characters by ruleset and faction (e.g. "Normal · Horde"), each with its own gold total. Click a group's heading to collapse it. The bags window's character list uses the same groups.
  - Tooltips (items, gold, Can craft, skill-ups, upgrades, XP and reputation bars) and `/af find` list only characters you can mail. Turn on "Show other rulesets and factions" in the options, or `/af rulesets`, to see the others too, in grey under their own heading and total.
  - Send to alt only offers characters you can mail, and gold today and this week (session stats) are counted per ruleset and faction.
  - Characters you haven't logged in on since updating count as being on yours until you do.
- **Waylaid Crates:** hovering a crate adds a grid of the materials it takes: a column per material, how many are needed, a row for each of your characters who has any, and the total. Green shows who has enough to fill it alone, and whether your characters have enough between them.

## Alts Forever 0.11.0

- **Legacy points to spend:** Legacy points are earned by your account but each character spends them separately, so it's easy to forget one. Logging in on a character with points to spend now says so in chat ("You have 13 Legacy points to spend on this character"). Earning a new point tells you how many of your characters can spend it. Thanks to the player who asked for this!
  - The overview has two new columns beside Rested, **Well Rested** (e.g. 3/5) and **Legacy** (points spent of the total each character can spend, e.g. 3/16, in orange while some are left), and hovering a character shows both. Each character's are read the next time you log in on them.
  - `/af legacy` lists every character's points and Well Rested rank. Turn the chat reminders off with "Legacy reminders" in the options, or `/af legacy off`.
- **Where they're resting:** rested XP in the overview (and on the XP bar's list of alts) is orange for a character logged out outside an inn or city, where it builds at a quarter of the speed, so you can spot who to move. Full stays blue.
- **Fixed: Well Rested is per character.** 0.10.0 read it as if it were account-wide, so every character's rested estimate used the rank of whoever you logged out on last. Each character now uses their own.

## Alts Forever 0.10.0

- **Upgrades for your characters:** hovering an item you could pass on (binds when equipped, not yet bound) lists which of your characters it would be an upgrade for, the slot and by how much, e.g. "Hands · +18%", or "empty slot". Characters up to 5 levels short show in grey with the level they can wear it at. A recipe shows the same for the item it makes ("Makes an upgrade for"); if that item binds on pickup, only characters who know the recipe or can learn it are listed. Items that are yours alone (bind on pickup or soulbound) show your own row.
  - Each character is judged by their role: the talent tab they've put most points in (melee, ranged, caster, healer, tank or feral, depending on class), or their class's usual levelling role under 10 points. Right-click a character in the overview and pick Upgrade role to choose it yourself, or type `/af role Name healer` (`auto` follows talents again).
  - Armour types and the step up to mail or plate at 40, weapon types, dual wield, "Classes:" lines and profession requirements are all checked. Rings and trinkets are compared with the weaker of the two worn, a two-hander with main and off hand together.
  - Turn it off with "Show upgrades" in the options, or `/af upgrades`.
- **Rested XP with Legacy's Well Rested:** the rested estimate for your logged-out characters now counts Well Rested's ranks (4% faster and a 4% higher cap per rank), read from your account's Legacy tree.
- **Controller support (Forever's Gamepad UI):** Alts Forever's windows now work with the D-pad. Focus jumps into a window when it opens, the D-pad moves between its buttons and shows their tooltips, A presses, B closes, and LT/RT switch between open windows.
  - Open the overview or the bags window with a key binding (Key Bindings > AddOns > Alts Forever) or a macro of `/af` or `/af bags` on a gamepad action bar.
  - A on a character in the overview opens their menu, which now also has Gear (the right-click menu has it too).
  - The Reputation panel and the icon picker have page buttons, and the bags window scrolls to the slot you move onto.
  - With the mouse and keyboard nothing changes.

## Alts Forever 0.9.1

- **Fixed: with EllesmereUI's bank, the Alts Forever button covered its Show Bags button.** It now sits at the left end of the header's buttons, in the bags and the bank.
- **Fixed: the minimap button could be dragged out of a minimap button collector** (EllesmereUI's tray, MinimapButtonButton and the like). While one holds it, the collector decides where it sits; dragging only moves it round the minimap when it's on the minimap itself. Hiding it with "Show minimap button" also updates MinimapButtonButton's grid.

## Alts Forever 0.9.0

- **Bags and bank window:** see any character's bags or bank slot by slot, as you last saw them, with stack counts, empty and free slots, quality borders and their gold. Show everything in one grid, or tick "By bag" for a section per bag or bank tab ("Red Linen Bag (7 / 8)"). Pick the character from a dropdown and switch between bags and bank. It plays the game's bag sounds as it opens and closes. Drag the corner to resize it: the width sets how many slots per row, the height how tall it gets before it scrolls, and both are remembered. Each character's slots are recorded the next time you log in on them or visit their bank; until then it shows their items with totals. Suggested by a player: thank you!
  - Open it from your own bags and bank: an entry at the bottom of the bag's portrait menu, or a small Alts Forever button in the header of Blizzard's bank and of ElvUI's and EllesmereUI's bags and bank.
  - Or from the overview's new bag button, by right-clicking a character in the overview, from the minimap button's menu, or with `/af bags` and `/af bank` (add a name for another character, e.g. `/af bank Tarnia`).
- **Options menu:** Open overview is always in the minimap button's menu now (it brings the overview to the front if it's already open), with Bags and bank below it.
- **Fixed: Settings... in the options menu** could be blocked by the game ("AddOn tried to call the protected function"). It now opens the Options page straight away, and in combat says it can't instead.
- **Windows stay in front:** the overview, Reputation, gear and bags windows come to the front when you click or open them, instead of drawing through each other.

## Alts Forever 0.8.0

- **Choose your tooltip icons:** pick the icons item tooltips use for bags, bank, mail and worn items, or words instead, from Options > AddOns > Alts Forever (or `/af icons`). The picker has recommended icons, a search by item or spell name, and every spell and item icon in the game to browse, with a preview. Hover an icon to see what it is.
- **New bag icon:** tooltips now show a white linen bag for bags. The red one is still in the picker if you prefer it.
- **Find an item across your characters:** `/af find linen` lists every item whose name contains "linen" on any character (bags, bank, mail or worn), biggest total first, with who has how many. Links are clickable.
- **Settings page:** Alts Forever now has its own page under Options > AddOns, with the logo, an Open overview button and all its settings (skill-up details, send mail to alts, session stats, minimap button), each explained when you hover it. The options menu has a Settings... entry that opens it.
- **A friendlier start:** on a new install, a short welcome in chat explains how to use Alts Forever and what to visit on each character. Logging in on a new character says it's now tracked, and the overview says how to add your other characters while it only knows one.
- **Translations:** Alts Forever now speaks German, French, Spanish (Spain and Latin America), Brazilian Portuguese, and Simplified and Traditional Chinese, following your game's language. Corrections from native speakers are very welcome.
- **Works on every language's client:** the "(0 skill-up recipes)" rule for gathering professions no longer depends on English profession names.
- **Fixed: the options menu with EllesmereUI's minimap.** Right-clicking the minimap button inside EllesmereUI's button tray opened the menu, but clicking any entry just closed it. Every entry works now.
- **Two copies enabled:** if two copies of Alts Forever are enabled at once (for example an old and a new install), only the first one runs and it says so in chat, so tooltips don't show everything twice and your saved data can't be mixed up.

## Alts Forever 0.7.0

- **Session stats (optional, off by default):** turn on "Show session stats" in the options menu or type `/af stats`.
  - Your XP bar shows this session's time, XP gained, and about how long to level at that pace.
  - Your bag gold shows gold gained or lost this session, today and this week across all your characters, in green or red.
  - A `/reload` doesn't reset the session. With it off, nothing changes.
- **Tidier tooltips:** item counts, the XP and reputation bar lists, and the professions in the overview's character tooltip are lined up in proper columns, so icons, numbers and totals sit exactly under each other, with any font or UI addon. Every line uses the tooltip's own font, so they're all the same size with UI addons like EllesmereUI. The breakdown and the "skill-ups to" notes are a lighter grey, easier to read on the default tooltip.
- **Overview window:** the XP percentages line up, and gathering professions (Fishing, Skinning, Herbalism) no longer say "(0 skill-up recipes)" when their few recipes (Fish Bowl, Camp Chair) have gone grey.
- **Gold with ElvUI and EllesmereUI bags:** hovering the gold in ElvUI's bags shows your gold across characters. EllesmereUI's bags keep their own gold summary; turn off its gold tracking (in EllesmereUI's bag options) to see Alts Forever's there instead.

## Alts Forever 0.6.0

- **Your alts on the XP bar:** hover the experience bar to see your other characters that are still levelling, with their level, XP and rested XP (including what they've built up while logged out), lined up in columns.
- **Your alts on the reputation bar:** hover the reputation bar to see your other characters' standing with the faction you're watching, e.g. "Friendly 8%  500 / 6000".
- Both work with Blizzard's bars, ElvUI's and EllesmereUI's.
- **New commands** for what could only be clicked before: `/af rep` opens the Reputation panel, `/af minimap` shows or hides the minimap button, and `/af sendmail` turns the send-to-alt arrow at the mailbox on or off. `/af help` lists them all.

## Alts Forever 0.5.0

- **Minimap button:** Alts Forever now has a normal minimap button: click for the overview, right-click for options, drag to move it. Hide it with "Show minimap button" in the options menu. With EllesmereUI it appears in its minimap button tray.
- **Your class colours:** character names use your custom class colours from EllesmereUI, ElvUI or addons like !ClassColors, instead of Blizzard's defaults, and follow them if you change them.
- **EllesmereUI look:** with EllesmereUI installed, Alts Forever's windows (overview, gear and reputation) take on your EllesmereUI theme, accent colour and font, including its square icon buttons. Without it, nothing changes. You can turn it off for Alts Forever in EllesmereUI's options (Blizz UI Enhanced > Blizzard Window Skins > Third-Party Addons).
- **ElvUI look:** with ElvUI installed, Alts Forever's windows get ElvUI's flat backdrop, close button and font, and the gear panel's item slots, the title-bar icon buttons and the mail window's Alts arrow match ElvUI's style. If you run both EllesmereUI and ElvUI, EllesmereUI's look is used.
- **New icon:** the addon list icon is the logo without its outer ring, so it's easier to make out at that size.

## Alts Forever 0.4.0

- **Reputation across your characters.** A new Reputation panel shows every character's standing with each faction side by side, e.g. "Honored 27%", coloured by standing. Hover a faction for the exact numbers. Open it with the reputation button in the overview's title bar. Standings are recorded as you play, without changing how your reputation window is expanded or collapsed.
- **Send to alt.** At the mailbox, a small arrow next to the To box lists your characters (your faction). Picking one fills in their name; nothing is sent until you press Send. Characters who can still skill up with what you've attached are marked, e.g. "skill-ups with 1 item", and listed first. Turn it off with "Send mail to alts" in the options menu.
- **Click instead of typing:**
  - Alts Forever is in the minimap's addon menu, the small number at the top of the minimap: click to open the overview, right-click for options.
  - The overview has an options button: skill-up details on/off, send mail to alts on/off, and memory use.
  - Right-click a character in the overview to forget them (with a confirmation). The row's tooltip says so.
- All the slash commands still work.

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
