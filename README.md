ItemWatch
=========

A World of Warcraft addon for tracking specific item counts — a movable,
resizable box you drag items into, with goals, per-item sounds, and a
minimap button.

Built for farming, collecting, or any situation where you need to keep an
eye on an exact item count without repeatedly opening your bags.

## Features

- **Item Box** — a movable, resizable container for everything you're
  tracking. Drag items from your bags straight onto it, right-click an
  icon inside to remove it.
- **Quick-Add popup** — track items you don't have yet by pasting a
  Wowhead link, typing an item ID, or shift-clicking an item straight
  into the field. Set a goal and sound in one step.
- **Per-item edit popup** — left-click any tracked icon to change its
  goal or pick its own custom "goal reached" sound (or mute it).
- **Per-item ding sounds** — no more one generic sound for everything;
  give each tracked item its own, so you know what just hit its goal
  without looking.
- **Shift-click to link, Ctrl-click to preview** — tracked icons behave
  like real item icons for chat links and equippable-gear previews.
- **Character-specific tracking** — each character keeps its own list,
  bags + reagent bag only, real-time (no bank/warbank tracking, so counts
  are always exactly accurate).
- **Blizzard Edit Mode support** for the box.
- **Combat / pet battle visibility toggles** — hide the box automatically
  if you'd rather it stay out of the way. Tracking keeps running in the
  background regardless.
- **Minimap button** — left-click to show/hide the box, right-click for
  settings. Built on LibDataBroker + LibDBIcon, so it's automatically
  compatible with minimap button "tray" addons (ElvUI's built-in one,
  Dominos, Bartender4, MBB, SexyMap, etc.).
- All the original `/iw` slash commands still work, unchanged — the box
  and popups are additional ways in, not replacements.
- Lightweight — event-driven, no polling.

## Installation

**Recommended:** install via [CurseForge](https://www.curseforge.com/wow/addons/item-watch).

**Manual install:**
1. Download the latest release, or clone this repo.
2. Copy the `ItemWatch` folder (including the `Libs` subfolder) into your
   WoW AddOns directory: `World of Warcraft/_retail_/Interface/AddOns/`
3. Restart WoW or `/reload`.

## Usage

**The easy way:**
1. Drag an item from your bags onto the box to start tracking it.
2. Left-click the icon inside the box to set a goal and pick a sound.
3. Right-click the icon to stop tracking it.

**For items you don't have yet:**
1. Click the "+" on the box (or right-click empty space inside it).
2. Paste a Wowhead link, type the item ID, or shift-click an item to fill
   the field automatically.
3. Set a goal and sound preference, click Track.

### Commands

| Command | Description |
|---|---|
| `/iw add <itemID>` | Start tracking an item |
| `/iw remove <itemID>` | Stop tracking an item |
| `/iw list` | List everything currently tracked |
| `/iw clear` | Remove all tracked items (asks to confirm) |
| `/iw lock` | Lock the box in place |
| `/iw unlock` | Unlock the box so you can move/resize it |
| `/iw goal <itemID> <amount>` | Set a target amount for an item |
| `/iw goal <itemID> clear` | Remove the goal for an item |
| `/iw sound <itemID> on\|off` | Toggle the goal-reached sound for an item |
| `/iw testsound` | Preview the default goal sound |
| `/iw options` | Open the settings panel |

Ctrl+Shift+Click an item in your bags also adds it directly, no item ID
needed (default Blizzard bag UI only).

## Settings

Find ItemWatch's settings under Options > AddOns > ItemWatch in-game, or
type `/iw options`, or right-click the minimap button. From there you can
set per-item sounds, combat/pet-battle visibility toggles, and show/hide
the minimap button.

## Notes

- Tracked items are saved per-character, so each character keeps their
  own independent list.
- The addon bundles LibStub, CallbackHandler-1.0, LibDataBroker-1.1, and
  LibDBIcon-1.0 in the `Libs` folder for the minimap button - these are
  widely-used shared libraries, not custom code.
- The Ctrl+Shift+Click add-from-bags shortcut only works with Blizzard's
  default bag UI. If you use a bag-replacement addon (Baganator,
  ArkInventory, Bagnon, etc.), use `/iw add <itemID>` or the Quick-Add
  popup instead.

## Contributing / Issues

Found a bug or have a feature idea? Open an issue — feedback and
suggestions welcome.

## License

MIT — see LICENSE for details.

---

If you find ItemWatch useful, consider supporting me on
[Ko-fi](https://ko-fi.com/nerdybertie) — totally optional, but always
appreciated! You can also find me on
[Twitch](https://www.twitch.tv/nerdybertie) or
[YouTube](https://www.youtube.com/@nerdybertie) - NerdyBertie
