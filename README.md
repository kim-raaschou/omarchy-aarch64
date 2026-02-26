# omarchy-aarch64

Install [Omarchy](https://github.com/basecamp/omarchy) on Arch Linux ARM (aarch64).

Based on **basecamp/omarchy** (`dev` branch) with three minimal patches for ARM compatibility.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/kim-raaschou/omarchy-aarch64/main/setup.sh | bash
```

## Prerequisites

- Arch Linux ARM (aarch64) with working pacman
- Running as root
- Internet connection

## What it does

1. Clones `basecamp/omarchy` (dev branch)
2. Patches for aarch64:
   - **guard.sh** — allows aarch64 (removes x86_64/limine/btrfs checks)
   - **Package list** — removes 7 unavailable packages, adds fuzzel + ncspot + pipewire
   - **Keybinding** — SUPER+Space launches fuzzel instead of Walker
3. Installs all packages (official via pacman, AUR via yay)
4. Deploys configs, themes, and 70+ bin scripts
5. Sets up SDDM with auto-login → Hyprland (via UWSM)
6. Applies Tokyo Night theme
7. Configures `WLR_ALLOW_ROOT=1` for running Hyprland as root

## Differences from upstream

| Component | Upstream | aarch64 |
|-----------|----------|----------|
| App launcher | Walker | Fuzzel |
| Music | Spotify | ncspot (TUI) |
| Architecture | x86_64 only | aarch64 |
| Boot | Limine + btrfs | Any |
| Root | Blocked | Allowed (WLR_ALLOW_ROOT) |

### Removed packages (x86_64 only)

`omarchy-walker` `omarchy-nvim` `1password-beta` `1password-cli` `spotify` (replaced by ncspot) `gpu-screen-recorder` `kernel-modules-hook`

### Added packages

`fuzzel` `ncspot` `pipewire` `pipewire-alsa` `pipewire-pulse` `pipewire-jack`

## Known limitations

Walker-dependent features are non-functional (they fail silently):

- Emoji picker (SUPER+CTRL+E)
- Clipboard manager (SUPER+CTRL+V)
- Walker theme/module integration in omarchy-menu

## After install

Reboot to start the desktop:

```bash
systemctl reboot
```

SDDM will auto-login and launch Hyprland.

## Credits

- [basecamp/omarchy](https://github.com/basecamp/omarchy) — the original Omarchy desktop
- [malik-na/omarchy-mac](https://github.com/malik-na/omarchy-mac) — ARM reference implementation
