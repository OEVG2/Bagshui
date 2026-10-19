# Bagshui for WoW 1.18.1 Clients
(Warning, Made with AI)

<h1>
<img src="Images/Logo.svg" width="204" align="left" alt="Bagshui">
<div width="100%">&nbsp;<br></div>
</h1>

**Feng shui for your bags:** A Vanilla WoW 1.12 (and WoW 1.18.1 Clients) inventory addon.<br><sup>Not for Classic or Retail; you have [so](https://www.curseforge.com/wow/addons/better-bags) [many](https://www.curseforge.com/wow/addons/ark-inventory) [options](https://www.curseforge.com/wow/search?class=addons&categories=bags-inventory&sortBy=popularity).</sup>


## About this fork

A fork of **Bagshui 1.5.16** for WoW 1.18.1 Clients, built on [ClassicAPI](https://github.com/brues-code/ClassicAPI) by Brues-Code.

- **Hide a bag's items:** right-click (or Ctrl+Click) a bag button to hide everything in it (profession bags, quivers, soul bags...). Saved per character; **Show Hidden** brings them back.
- **Multi-account Catalog:** items and gold from your other WoW accounts on the same computer show up in the Catalog and item tooltips. See [Sharing between accounts](#sharing-between-accounts).
- **Requires ClassicAPI.** Without it Bagshui disables itself and leaves your settings alone. See [Requirements](#requirements).
- **Drop-in replacement for upstream:** same `Bagshui` folder and `BagshuiData` SavedVariables. Do not run both.
- See the [Changelog](Changelog.md) for everything that changed.

## Features

- Single-window inventory for Bags, Bank, and Keyring.
- [Customizable layout and design](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Profiles) with automatic grouping and sorting.
- [Categorization](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Categories) via [rules](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Rules) and item lists.
- Per-inventory and account-wide [search](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Searching).
- Offline viewing of any character’s inventory and [item counts in tooltips](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Item-Information#info-tooltip).
- Identification of [profession reagents and crafted items](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Professions).<br><sup>Updated when the crafting window is opened.</sup>
- Color tinting of unusable items.
- Badges to indicate stock changes, quality, quest items, and unusability.
- Empty slot stacking and custom graphics for profession bag slots.
- Automated bag swapping – no more manual item shuffling!
- Selling protection to safeguard valuable items.
- Clam (Open Container), Disenchant, Pick Lock, and Hearthstone buttons.
- [Colorblind mode](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Accessibility#colorblind-mode) to help identify item quality and unusability.
- Plenty of other little niceties like item restacking, pfUI skinning, and more.

<details>

<summary>Recommended if you like…</summary>

> AdiBags, ArkInventory, Baganator, Baggins, BetterBags, EngInventory/EngBags, TBag.
> And with “[OneBagshui](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/FAQ#how-do-i-switch-to-the-onebag-style-layout)”: Bagnon, Combuctor, Inventorian, LiteBag, OneBag3, SUCC-bag.

</details>

## Documentation

⬇️ [Installation](#installation)
📕 [Wiki](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki)
🙋 [FAQ](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/FAQ)
🐾 [Walkthroughs](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Walkthroughs)
🕝 [Changelog](Changelog.md)

## Requirements

This fork needs [ClassicAPI](https://github.com/brues-code/ClassicAPI) (`ClassicAPI.dll`) loaded through [VanillaFixes](https://github.com/hannesmann/vanillafixes):

1. Install VanillaFixes if you haven't already.
2. Copy `ClassicAPI.dll` into your game folder and add it to `dlls.txt`.
3. Launch the game with `VanillaFixes.exe`.

Without ClassicAPI, Bagshui prints a message in chat and disables itself (your settings are left untouched).

To check that it's loaded, run `/script DEFAULT_CHAT_FRAME:AddMessage(tostring(CLASSIC_API_VERSION))` in game. A number means it is.

**Optional:** [Nampower](https://github.com/pepopo978/nampower) enables [sharing between accounts](#sharing-between-accounts). Without it, everything else works normally.

## Installation

Make sure you meet the [Requirements](#requirements) first.

### Easy mode (recommended)

Use [GitAddonsManager](https://woblight.gitlab.io/overview/gitaddonsmanager/).
<sup>Or any tool that supports Git.</sup>

### Manual

1. Download `Bagshui.zip` from the latest release on this repository's **Releases** page.
2. Extract the zip file.
3. Ensure the resulting folder is named `Bagshui` and rename if needed.
4. Move that folder to `[Path\To\WoW]\Interface\Addons`.
5. Ensure the structure is `Interface\Addons\Bagshui\Bagshui.toc`.
   <sup>_These are all **wrong**:_
   × `Bagshui\Bagshui\Bagshui.toc`
   × `Bagshui-main\Bagshui.toc`
   × `Bagshui\Bagshui-main\Bagshui.toc`
   </sup>

## Sharing between accounts

Bagshui already shares items and gold between the characters on one account. With **Nampower's file functions** it also shares them with your **other accounts on the same computer**: their characters (items, equipped gear and gold) appear in the Catalog, Catalog search and item tooltips, and you can view their bags and bank from the Character menu (read-only).

Setup: in your launcher, enable **Mods → Nampower**. That's it. Check with `/script DEFAULT_CHAT_FRAME:AddMessage(tostring(WriteCustomFile))` (it should print `function`).

How it works: each character writes one file (`Bagshui_<Name>_<Realm>.txt`) to the `CustomData` folder, which every client launched from the same install shares, and a short `Bagshui_roster.txt` lists who has one. At startup Bagshui reads the other accounts' files. No scripts, passwords or pairing.

- Log in once on each account for its characters to appear on the others. After that, other accounts' data is as fresh as that character's last logout (or last change, since it saves while you play).
- Other accounts' characters are loaded when you log in or `/reload`.
- You can view their bags, bank and keyring from the Character menu like your own alts (offline view). They're also listed in the Character Data manager (marked "other account"), but can only be deleted from the account they belong to.
- Characters that exist in this account's own saved data always take priority.
- Deleting an alt in the Character Data manager also stops sharing it with your other accounts.
- Without Nampower this does nothing and costs nothing.

Inspired by [Bagertz](https://github.com/Salahaja/Bagertz) (tooltip counts across accounts), which uses the same Nampower folder.

## Compatibility

### Functionality

<table>

<tr>
<td>

### Auction and Mail

<sup>Right-click/Alt+click attach</sup>

</td>
<td>

- Blizzard UI
- [aux](https://github.com/gwetchen/aux-addon)
- [Mail](https://github.com/EinBaum/Mail)
- [Postal Returned](https://web.archive.org/web/20250622152236/https://github.com/veechs/Postal-Returned) / Postal / CT_MailMod

</td>
</tr>

<tr>
<td>

### Cooldown counts

</td>
<td>

- [OmniCC](https://github.com/Otari98/OmniCC)
- [pfUI](https://shagu.org/pfUI/)
- [ShaguTweaks](https://shagu.org/ShaguTweaks/)
- [Turtle Dragonflight](https://github.com/TheLinuxITGuy/Turtle-Dragonflight)

</td>
</tr>

<tr>
<td>

### Interface replacement

</td>
<td>

- [pfUI](https://shagu.org/pfUI/) skin
  <sup>Manage in **pfUI Config** (`/pfui`) > **Components** > **Skins**</sup>

</td>
</tr>

<tr>
<td>

### [Rule functions](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Rules#available-rule-functions)

</td>
<td>

- `Outfit()` - [ItemRack](https://turtle-wow.fandom.com/wiki/ItemRack) and [Outfitter](https://github.com/pepopo978/Outfitter)
- `Wishlist()` - [AtlasLoot](https://turtle-wow.fandom.com/wiki/AtlasLoot)

</td>
</tr>

<tr>
<td>

### WoW 1.18.1 Clients

</td>
<td>

- **Guild Bank** right-click to deposit.
- [`Transmog()`](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui/wiki/Rules#available-rule-functions) collection queries.<br><sup>Requires [Tmog](https://github.com/Otari98/Tmog) and [Bagshui-Tmog](https://web.archive.org/web/20250622152236/https://github.com/veechs/Bagshui-Tmog).

</td>
</tr>

</table>

<sup>If installed, [SuperWoW](https://github.com/balakethelock/SuperWoW) provides charge counts (the `×#` overlay for multi-use items) slightly more efficiently. This is pretty minor since you'll have the functionality regardless.</sup>

### Languages

If Bagshui has not been localized for your client, many items will not be correctly identified by the built-in categorization[^1]. Please consider [contributing a translation](Locale/Readme.md) if you'd like to have full functionality!

- English (enUS)
- Chinese (zhCN)

[^1]: In Vanilla, a _lot_ of item identification must be done either by parsing tooltips or hardcoding item IDs. Bagshui leans toward the former, and therefore is highly dependent on localization.

## Credits

Bagshui owes [so much to so many people](Credits.md), including its original author, [veechs](https://www.buymeacoffee.com/veechs).

<br><br>
