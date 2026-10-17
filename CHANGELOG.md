# ItemWatch

## v2.3.2

### Fixed
- The box no longer pops back up after combat or a pet battle when you had hidden it yourself. A box you hide stays hidden until you show it again, and that now survives /reload and logging out.

### New
- "Reset box position and show it" button under Visibility in the settings (or type `/iw reset`). It puts the box back in the center of the screen and unhides it, which helps if the minimap button is hidden.
- Alt-click a vendor item that is bought with items (cloth, ore, gems) and ItemWatch tracks those items for you, with the goal set to the amount needed. Alt-click again for a second purchase and the goals add up.
- Items added from a vendor also count your bank and warband bank. Any item can switch this on or off in its edit popup (left-click the icon). The rest of the box still counts bags only.
- Added "HandyNotes: Seeking the Soulstones" to the list of other NerdyBertie addons on the workshop page.
- "Hide the item box" checkbox under Visibility, plus `/iw show` and `/iw hide` commands.
- "Show Shopping List" button in the settings to reopen a list you closed (same as `/iw shopping`).
- "Hide Shopping List during combat" checkbox. The list comes right back when combat ends and nothing is lost.

## v2.3.1

### Fixed
- Fixed an error ("attempt to call a nil value") that appeared after WoW patch 12.1.5. Blizzard removed the old item lookup function the item box relied on, so tracked items could be added but not drawn or refreshed until a /reload. The box now draws and updates normally again.
- Adding items from other addons, such as Ctrl-clicking a holiday's shopping list in Holiday Herald, works right away.

### Changed
- Added support for patch 12.1.5.
- The addon is now listed as "ItemWatch & Shopping List". Your tracked items and shopping lists are unchanged.

## v2.3.0

### New
- The Shopping List now holds more than one recipe at a time. Leveling a profession? Add the wrist guards, the chest and the legs, and ItemWatch adds up the materials they share, so three recipes that all use metal bars show one combined bar total.
- Each recipe on the list has its own "how many" box and an x to remove just that recipe. Clicking "Add to Shopping List" on a recipe that's already there adds one more.
- New "Clear all" button (it asks first) to start over.
- Hover Practically Pork, Plant Protein or Thalassian Fillet in the list to see where it comes from (looting and/or salvaging). Thalassian Fillet, which can only be made by salvaging, gets a small [salvage only] tag.
- The list scrolls with the mouse wheel when it gets long.

### Changed
- The X on the Shopping List window now just hides it and keeps your list. Type `/iw shopping` to bring it back.
- A Shopping List you had open when you updated carries over automatically.

## v2.2.6

### New
- The NerdyBertie page in Options > AddOns is now NerdyBertie's Addon Workshop, with a mascot and a list of my other addons (the ones you have installed are marked).

### Fixed
- The addon list on the Workshop page could show up blank until you reopened it.
