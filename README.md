# Hoopoo Packages

Personal pacman repository for Hoopoo Linux — packages not available in standard Arch repos.

## Add to pacman

First install the keyring to trust Hoopoo packages:

```bash
sudo pacman-key --recv-keys 070030E5D914817BA797F66AAF1C8F036A5E73FD --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 070030E5D914817BA797F66AAF1C8F036A5E73FD
sudo pacman -U https://pkgs.hoopoo.net/stable/x86_64/hoopoo-keyring-1-1-any.pkg.tar.zst
```

Then add to `/etc/pacman.conf`:

```ini
[hoopoo]
SigLevel = Required DatabaseOptional
Server = https://pkgs.hoopoo.net/stable/$arch
```

For testing/latest packages, use the edge channel:

```ini
[hoopoo]
SigLevel = Required DatabaseOptional
Server = https://pkgs.hoopoo.net/edge/$arch
```

## Channels

- `stable` — production packages, promoted from edge when tested
- `edge` — latest versions, built automatically on push or upstream update

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
| hoopoo-keyring | local | Hoopoo Linux PGP keyring |
| elephant | AUR | Walker data provider daemon |
| elephant-* | AUR | Walker provider plugins |
| aether | [omacom/aether](https://github.com/omacom/aether) | App/theme launcher |
| asdcontrol | [omakasui/asdcontrol](https://github.com/omakasui/asdcontrol) | Apple Display brightness control |
| dell-xps-touchpad-haptics | local | Dell XPS touchpad haptics |
| ghost | [ferdousbhai/ghost](https://github.com/ferdousbhai/ghost) | Writing app |
| hoopoo-nvim | local | Neovim LazyVim config |
| intel-ipu7-camera | local | Intel IPU7 camera driver |
| lib32-nvidia-580xx-utils | AUR | Nvidia 580xx 32-bit utils |
| limine-mkinitcpio-hook | AUR | Limine mkinitcpio hook |
| limine-snapper-sync | AUR | Limine snapper sync |
| linux-ptl | local | Linux kernel for Panther Lake |
| localsend | [localsend/localsend](https://github.com/localsend/localsend) | Local file sharing |
| macbook12-spi-driver-dkms | AUR | MacBook SPI keyboard driver |
| nvidia-580xx-utils | AUR | Nvidia 580xx utils |
| python-terminaltexteffects | AUR | Terminal text effects |
| qmk-hid | AUR | QMK HID for Framework keyboard |
| spotify | AUR | Spotify music client |
| tobi-try | [tobi/try](https://github.com/tobi/try) | Shell try-before-you-install tool |
| ttf-ia-writer | AUR | iA Writer fonts |
| tuxedo-drivers-nocompatcheck-dkms | AUR | Tuxedo keyboard backlight |
| typora | AUR | Markdown editor |
| tzupdate | AUR | Timezone updater |
| ufw-docker | AUR | UFW Docker integration |
| v4l2-relayd | AUR | V4L2 relay daemon |
| vi | AUR | Classic vi editor |
| walker | AUR | Wayland app launcher |
| yaru-*-theme | AUR | Yaru icon/GTK themes |
| yay | [Jguer/yay](https://github.com/Jguer/yay) | AUR helper |
| yt6801-dkms | AUR | YT6801 ethernet DKMS driver |
