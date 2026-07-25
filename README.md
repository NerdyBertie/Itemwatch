# Itemwatch
A WoW addon for tracking item counts in your bags with movable icon+count displays

Itemwatch is a lightweight World of Warcraft addon for tracking specific item counts in your bags — movable icon + number displays you can drop anywhere on screen.

Built for farming, collecting, or any situation where you need to keep an eye on an exact item count without repeatedly opening your bags.

## Features

- Track any item by ID — grab it from the item's Wowhead URL (e.g. `wowhead.com/item=12345` → ID is `12345`)
- Movable, draggable frames — position them wherever fits your UI
- Auto-updates whenever your bag contents change
- Lock/unlock frame positions so you don't accidentally bump them
- Tooltip on hover shows full item info
- Lightweight — event-driven, no polling

## Installation

**Recommended:** install via [CurseForge](https://www.curseforge.com/wow/addons/itemwatch-bag-item-counter)

**Manual install:**
1. Download the latest release, or clone this repo
2. Copy the `ItemWatch` folder into your WoW AddOns directory:
   `World of Warcraft/_retail_/Interface/AddOns/`
3. Restart WoW or `/reload`

## Usage

| Command | Description |
|---|---|
| `/iw add <itemID>` | Start tracking an item |
| `/iw remove <itemID>` | Stop tracking an item |
| `/iw list` | List everything currently tracked |
| `/iw lock` | Lock frame positions in place |
| `/iw unlock` | Unlock frames so you can drag them |

### Quick start

1. Find an item on Wowhead and grab its item ID from the URL
2. `/iw add <itemID>`
3. `/iw unlock`, then drag the new icon wherever you want it
4. `/iw lock` to keep it in place

The count updates automatically as your bags change.


## Contributing / Issues

Found a bug or have a feature idea? [Open an issue](../../issues) — feedback and suggestions welcome.

## License

MIT — see [LICENSE](LICENSE) for details.

---

# Screenshots
<img width="363" height="94" alt="itemwatch" src="https://github.com/user-attachments/assets/b9dbad05-91c8-4a84-be03-7aabfd7661a4" />
<img width="213" height="161" alt="itemwatch2" src="https://github.com/user-attachments/assets/e3e0e6c9-df15-46e8-9d44-b69393e9f496" />

Built with AI assistance (Claude) and refined for personal use.
