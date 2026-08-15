<img width="200" height="200" alt="ItemWatch_Wago_optimized" src="https://github.com/user-attachments/assets/3e1312c6-2d85-4927-9d93-1b7ab4f637f2" />

ItemWatch
=========

A World of Warcraft addon for tracking specific item counts — a movable,
resizable box you drag items into, with goals, per-item sounds, and a
minimap button. Now also builds a shopping list straight from any
crafting recipe.

Built for farming, collecting, or any situation where you need to keep an
eye on an exact item count without repeatedly opening your bags.

## Features

- **Item Box** — a movable, resizable container for everything you're
  tracking. Drag items from your bags straight onto it, right-click an
  icon inside to remove it.
- **Recipe Shopping List** — click "Add to Shopping List" on any recipe
  in the Professions Recipes tab, and ItemWatch reads its full reagent
  list and builds a shopping list for you automatically. Making more
  than one? Set the quantity right in the window ("Crafting: __ x this
  recipe") and every reagent's needed amount updates live - no need to
  re-add the recipe. Required reagents track live progress (counting
  bank, reagent bank, and warband bank, not just bags), optional/
  finishing reagents show as a plain reminder, and reagents you can't
  buy on the Auction House are flagged "[vendor/earned only]" instead of
  silently vanishing. The window is movable, resizable, lockable,
  persists across logout/reload, and asks before replacing an already-
  open list so an accidental click won't wipe your progress.
- **Quick-Add popup** — track items you don't have yet by pasting a
  Wowhead link, typing an item ID, or shift-clicking an item straight
  into the field. Set a goal and sound in one step.
- **Per-item edit popup** — left-click any tracked icon to change its
  goal or pick its own custom "goal reached" sound (or mute it).
- **Per-item ding sounds** — no more one generic sound for everything;
  give each tracked item its own, so you know what just hit its goal
  without looking. Includes plenty of fun presets alongside the standard
  ones - Commander Ulthok, Cat Meow, Aquatic Form Burp, Illidan, a Brann
  Bronzebeard easter egg section, and grouped "Horde Legends" (Thrall,
  Sylvanas, Baine, Monte Gazlowe) and "Alliance Champions" (Genn
  Greymane, Tyrande, Magni, Gelbin) sections.
- **Shift-click to link, Ctrl-click to preview** — tracked icons behave
  like real item icons for chat links and equippable-gear previews.
- **Character-specific tracking** — each character keeps its own list.
  The main Item Box is deliberately bags + reagent bag only, real-time,
  so counts are always exactly accurate (no bank/warband padding the
  number). The Shopping List is the one place that does check your bank
  and warband, since it's answering a different question - "do I still
  need to go buy this."
- **Blizzard Edit Mode support** for the box.
- **Combat / pet battle visibility toggles** — hide the box automatically
  if you'd rather it stay out of the way. Tracking keeps running in the
  background regardless.
- **Minimap button** — left-click to show/hide the box, right-click for
  settings. Built on LibDataBroker + LibDBIcon, so it's automatically
  compatible with minimap button "tray" addons (ElvUI's built-in one,
  Dominos, Bartender4, MBB, SexyMap, etc.).
- **In-game documentation** — the settings panel has expandable
  sub-pages covering how to use ItemWatch, the Recipe Shopping List,
  practical usage ideas (like Auction House shopping lists built from
  the main box), and contact/support info.
- **What's New popup** — a quick highlight reel shows once after each
  update (and doubles as an intro if you're new to ItemWatch). Bring it
  back any time with `/iw whatsnew`.
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

**Building a shopping list from a recipe:**
1. Open any profession's Recipes tab and select a recipe.
2. Click "Add to Shopping List."
3. Required reagents show live have/needed progress (bank + reagent bank
   + warband bank included), optional reagents show as a reminder, and
   anything you can't buy is flagged "[vendor/earned only]."
4. The window sticks around - move it, resize it, lock it, or just leave
   it open. It'll still be there if you log out mid-farm.

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
| `/iw addrecipe` | Add the currently-open recipe to the Shopping List |
| `/iw whatsnew` | Show the What's New popup again |
| `/iw options` | Open the settings panel |

Ctrl+Shift+Click an item in your bags also adds it directly, no item ID
needed (default Blizzard bag UI only).

## Settings

Find ItemWatch's settings under Options > AddOns > ItemWatch in-game, or
type `/iw options`, or right-click the minimap button. From there you can
set per-item sounds, combat/pet-battle visibility toggles, and show/hide
the minimap button.

The settings panel also has an expandable "+" with sub-pages: **Helpful
Information** (how everything works), **Shopping List** (how the
recipe-based shopping list works), **Practical Uses** (real workflows
like building an Auction House list from the main box), **Contact/Support**,
and **About**.

## Notes

- Tracked items are saved per-character, so each character keeps their
  own independent list.
- The addon bundles LibStub, CallbackHandler-1.0, LibDataBroker-1.1, and
  LibDBIcon-1.0 in the `Libs` folder for the minimap button - these are
  widely-used shared libraries, not custom code.
- **Manual install / cloning:** make sure the `Libs` folder (and its four
  subfolders) comes along with `ItemWatch.lua` and `ItemWatch.toc` into
  your AddOns folder. If you use GitHub's green "Code" button and download
  the ZIP, this happens automatically. If you're grabbing files one at a
  time, don't skip `Libs` - without it, the minimap button won't appear
  (the rest of the addon still works fine, it just quietly skips that
  one feature).
- The Ctrl+Shift+Click add-from-bags shortcut only works with Blizzard's
  default bag UI. If you use a bag-replacement addon (Baganator,
  ArkInventory, Bagnon, etc.), use `/iw add <itemID>` or the Quick-Add
  popup instead.

## Contributing / Issues

Found a bug or have a feature idea? Open an issue — feedback and
suggestions welcome.

---

I only update on Curseforge, Github, Wago, and WoWInterface. 
Curseforge and Github are preferred, however I don't update anywhere
besides these aforementioned sites. 

---


## License

MIT — see LICENSE for details.

---

If you find ItemWatch useful, consider supporting me on
[Ko-fi](https://ko-fi.com/nerdybertie) — totally optional, but always
appreciated! You can also find me on
[Twitch](https://www.twitch.tv/nerdybertie) or
[YouTube](https://www.youtube.com/@nerdybertie) - NerdyBertie

<img width="1055" height="607" alt="itemwatchmainnew" src="https://github.com/user-attachments/assets/95d1f0b5-77d5-49d9-b297-0351a45647b8" />
<img width="1161" height="700" alt="itemwatchnewopts" src="https://github.com/user-attachments/assets/d51bb6af-dad9-4952-af1f-d91701ce453d" />
<img width="530" height="350" alt="iwaddmenu" src="https://github.com/user-attachments/assets/3f6a5d5d-3e05-493f-a157-9c02a9032ead" />
<img width="668" height="579" alt="thisItemwatchnewfeatureshopping" src="https://github.com/user-attachments/assets/b4883c68-c959-4c96-ad3a-d2c928c70676" />
<img width="1003" height="775" alt="newsounds2" src="https://github.com/user-attachments/assets/8f3daf1a-28c9-4d5e-9d32-cfd051182c03" />
<img width="383" height="304" alt="IWcommands" src="https://github.com/user-attachments/assets/837dc0c2-468b-4e16-a516-1fe7fcb97c74" />
<img width="879" height="523" alt="itwwhatsnew" src="https://github.com/user-attachments/assets/27327253-41ef-4bed-bd96-e73339bfad8f" />
