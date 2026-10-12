# Hoopoo Packages

Personal pacman repository for [Hoopoo](https://github.com/rawalrauf/omarchy) — packages not available in standard Arch repos.

## Add to pacman

```ini
[hoopoo]
SigLevel = Optional TrustAll
Server = https://github.com/rawalrauf/hoopoo-pkgs/releases/download/stable
```

## Branches

- `stable` — tested, used for installs
- `edge` — auto-syncs upstream every 6h, built automatically on push

## Adding a package

Create `pkgbuilds/<pkgname>/PKGBUILD` and optionally `pkgbuilds/<pkgname>/.hoopoo/package.json`.

### .hoopoo/package.json fields

```json
{
  "source": "local",

  "gpg_keys": ["KEY_ID_1", "KEY_ID_2"],

  "nocheck": "true",

  "hoopoo_deps": ["other-hoopoo-package"],

  "upstream": {
    "watch": {
      "github": "owner/repo",
      "pattern": "v?(?P<version>[0-9]+(?:\\.[0-9]+)*)"
    }
  }
}
```

- `gpg_keys` — GPG key IDs to import before building (for signature verification)
- `nocheck` — set to `"true"` to skip the `check()` function (use when checkdepends are unavailable)
- `hoopoo_deps` — other packages from this repo needed at build time as dependencies
- `upstream.watch` — enables auto-sync; use `\\` to escape backslashes in regex patterns

**Important:** In JSON strings, backslashes must be doubled. So `\.` becomes `\\.` and `\(` becomes `\\(`.

## Packages

| Package | Source | Description |
|---------|--------|-------------|
| elephant | AUR | Walker data provider daemon |
| elephant-* | AUR | Walker provider plugins |
| aether | omacom | App/theme launcher |
| asdcontrol | omacom | Apple Display brightness control |
| dell-xps-touchpad-haptics | omacom | Dell XPS touchpad haptics |
| ghost | omacom | Writing app |
| hoopoo-nvim | omacom | Neovim LazyVim config |
| intel-ipu7-camera | omacom | Intel IPU7 camera driver |
| lib32-nvidia-580xx-utils | omacom | Nvidia 580xx 32-bit utils |
| limine-mkinitcpio-hook | omacom | Limine mkinitcpio hook |
| limine-snapper-sync | omacom | Limine snapper sync |
| linux-ptl | omacom | Linux kernel for Panther Lake |
| localsend | omacom | Local file sharing |
| macbook12-spi-driver-dkms | omacom | MacBook SPI keyboard driver |
| nvidia-580xx-utils | omacom | Nvidia 580xx utils |
| python-terminaltexteffects | omacom | Terminal text effects |
| qmk-hid | omacom | QMK HID for Framework keyboard |
| spotify | AUR | Spotify music client |
| tobi-try | omacom | Toast notifications |
| ttf-ia-writer | omacom | iA Writer fonts |
| tuxedo-drivers-nocompatcheck-dkms | omacom | Tuxedo keyboard backlight |
| typora | omacom | Markdown editor |
| tzupdate | omacom | Timezone updater |
| ufw-docker | AUR | UFW Docker integration |
| v4l2-relayd | AUR | V4L2 relay daemon |
| vi | omacom | Classic vi editor |
| walker | omacom | Wayland app launcher |
| xdg-terminal-exec | omacom | XDG terminal launcher spec |
| yaru-*-theme | omacom | Yaru icon/GTK themes |
| yay | omacom | AUR helper |
| yt6801-dkms | omacom | YT6801 ethernet DKMS driver |
