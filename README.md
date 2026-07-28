ItemWatch

A lightweight World of Warcraft addon for tracking specific item counts in your bags — movable icon + number displays you can drop anywhere on screen.

Built for farming, collecting, or any situation where you need to keep an eye on an exact item count without repeatedly opening your bags.

Features
Track any item by ID — grab it from the item's Wowhead URL (e.g. wowhead.com/item=12345 → ID is 12345)
Ctrl+Shift+Click an item in your bags to add it directly (default Blizzard bag UI only)
Movable, draggable frames — position them wherever fits your UI
Character-specific tracking — each character keeps their own list
Optional goals — set a target amount, the display shows count/goal and turns green when met
Optional sound alert when a goal is reached, toggleable per item
Clear all tracked items at once, with a confirmation prompt
Auto-updates whenever your bag contents change
Lock/unlock frame positions so you don't accidentally bump them
Tooltip on hover shows full item info
Lightweight — event-driven, no polling
Installation

Recommended: install via CurseForge

Manual install:

Download the latest release, or clone this repo
Copy the ItemWatch folder into your WoW AddOns directory: World of Warcraft/_retail_/Interface/AddOns/
Restart WoW or /reload
Usage
Command	Description
Ctrl+Shift+Click an item in bags	Add it directly, no item ID needed
/iw add <itemID>	Start tracking an item
/iw remove <itemID>	Stop tracking an item
/iw list	List everything currently tracked
/iw clear	Remove all tracked items (asks to confirm)
/iw lock	Lock frame positions in place
/iw unlock	Unlock frames so you can drag them
/iw goal <itemID> <amount>	Set a target amount for an item
/iw goal <itemID> clear	Remove the goal for an item
/iw sound <itemID> on|off	Toggle the goal-reached sound for an item
Quick start
Find an item on Wowhead and grab its item ID from the URL, or just Ctrl+Shift+Click it in your bags
/iw add <itemID> (skip this if you used the click method)
/iw unlock, then drag the new icon wherever you want it
/iw lock to keep it in place

Optionally, set a goal so the icon shows your progress and dings when you hit it:

/iw goal 256963 50

The count updates automatically as your bags change.

Notes
Tracked items are saved per-character, so each character keeps their own independent list
The Ctrl+Shift+Click add-from-bags shortcut only works with Blizzard's default bag UI. If you use a bag-replacement addon (Baganator, ArkInventory, Bagnon, etc.), use /iw add <itemID> instead
Screenshots

(add your screenshots here once uploaded)

Contributing / Issues

Found a bug or have a feature idea? Open an issue — feedback and suggestions welcome.

License

MIT — see LICENSE for details.
