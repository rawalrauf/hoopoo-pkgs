# Hoopoo Packages

Personal pacman repository for [Hoopoo](https://github.com/rawalrauf/omarchy) — packages not available in standard Arch repos.

## Add to pacman

```ini
[hoopoo]
SigLevel = Optional TrustAll
Server = https://github.com/rawalrauf/hoopoo-pkgs/releases/download/main/$arch
```

## Packages

| Package | Source | Description |
|---------|--------|-------------|
| elephant | AUR | Walker data provider daemon |
| elephant-* | AUR | Walker provider plugins |
| asdcontrol | omacom | Apple Display brightness control |
| aether | omacom | App launcher |
| omarchy-nvim | omacom | Neovim config |
| tobi-try | omacom | Toast notifications |
| typora | omacom | Markdown editor |
| xdg-terminal-exec | - | XDG terminal launcher spec |
| yaru-icon-theme | omacom | Icon theme |
| tzupdate | omacom | Timezone updater |
| ufw-docker | omacom | UFW Docker integration |
| yay | omacom | AUR helper |

## Branches

- `main` — stable, manually tested
- `edge` — auto-tracks upstream, built via GitHub Actions
