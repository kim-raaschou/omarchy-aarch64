#!/bin/bash
# =============================================================================
# Omarchy aarch64 Setup
# Installs basecamp/omarchy (dev branch) on Arch Linux ARM with minimal patches
# https://github.com/kim-raaschou/omarchy-aarch64
# =============================================================================

main() {
set -euo pipefail

OMARCHY_DIR="${HOME}/.local/share/omarchy"
OMARCHY_REPO="https://github.com/basecamp/omarchy.git"
OMARCHY_BRANCH="dev"

info()  { printf '\n\033[1;34m>>>\033[0m %s\n' "$1"; }
ok()    { printf '\033[1;32m  OK:\033[0m %s\n' "$1"; }
warn()  { printf '\033[1;33m  WARN:\033[0m %s\n' "$1"; }
die()   { printf '\033[1;31m  ERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# --- Preflight ---
[[ "$(uname -m)" == "aarch64" ]] || die "This script is for aarch64 only."
[[ "$(id -u)" == "0" ]]          || die "Run as root."

echo ""
echo "  Omarchy aarch64 Setup"
echo "  basecamp/omarchy on Arch Linux ARM"
echo ""

# =========================================================================
# Step 1: System update
# =========================================================================
info "Step 1/14: Updating system and installing base packages..."
pacman -Syu --noconfirm
pacman -S --needed --noconfirm base-devel git
ok "System updated"

# =========================================================================
# Step 2: Clone omarchy
# =========================================================================
info "Step 2/14: Cloning basecamp/omarchy (${OMARCHY_BRANCH} branch)..."
if [ -d "${OMARCHY_DIR}" ]; then
    git -C "${OMARCHY_DIR}" pull --ff-only || true
    ok "Omarchy repo updated"
else
    mkdir -p "$(dirname "${OMARCHY_DIR}")"
    git clone -b "${OMARCHY_BRANCH}" "${OMARCHY_REPO}" "${OMARCHY_DIR}"
    ok "Omarchy repo cloned"
fi

# =========================================================================
# Step 3: Patch guard.sh
# =========================================================================
info "Step 3/14: Patching guard.sh for aarch64..."
cat > "${OMARCHY_DIR}/install/preflight/guard.sh" << 'GUARD'
# Patched for aarch64 -- original checks x86_64, limine, btrfs, non-root
if [[ ! -f /etc/arch-release ]]; then
  echo "Omarchy requires Arch Linux"; exit 1
fi
echo "Guards: OK (aarch64)"
GUARD
ok "guard.sh patched"

# =========================================================================
# Step 4: Patch package list
# =========================================================================
info "Step 4/14: Patching package list for aarch64..."
PKGFILE="${OMARCHY_DIR}/install/omarchy-base.packages"

# Remove packages unavailable on aarch64
for pkg in omarchy-walker omarchy-nvim 1password-beta 1password-cli \
           spotify typora gpu-screen-recorder kernel-modules-hook; do
    sed -i "/^${pkg}$/d" "${PKGFILE}"
done
ok "Removed 8 unavailable packages"

# Add aarch64-compatible packages
for pkg in fuzzel pipewire pipewire-alsa pipewire-pulse pipewire-jack; do
    if ! grep -q "^${pkg}$" "${PKGFILE}"; then
        echo "${pkg}" >> "${PKGFILE}"
    fi
done
ok "Added aarch64 packages (fuzzel, pipewire)"

# =========================================================================
# Step 5: Create build user (makepkg/yay refuse to run as root)
# =========================================================================
info "Step 5/14: Setting up build user..."
if ! id builder &>/dev/null; then
    useradd -m builder
fi
echo "builder ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
chmod 440 /etc/sudoers.d/builder
ok "builder user ready"

# =========================================================================
# Step 6: Bootstrap yay (AUR helper)
# =========================================================================
if ! command -v yay &>/dev/null; then
    info "Step 6/14: Installing yay from AUR..."
    tmpdir=$(sudo -u builder mktemp -d)
    sudo -u builder git clone https://aur.archlinux.org/yay-bin.git "${tmpdir}/yay-bin"
    sudo -u builder bash -c "cd '${tmpdir}/yay-bin' && makepkg -si --noconfirm"
    rm -rf "${tmpdir}"
    ok "yay installed"
else
    info "Step 6/14: yay already installed"
fi

# =========================================================================
# Step 7: Install packages
# =========================================================================
info "Step 7/14: Installing packages (this will take a while)..."

# Read package list (skip comments and blanks)
PKGS=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "${line}" | xargs)"
    [[ -z "${line}" ]] && continue
    PKGS+=("${line}")
done < "${PKGFILE}"

# Separate official repo packages from AUR packages
AVAILABLE=$(pacman -Sql 2>/dev/null || true)
OFFICIAL=()
AUR=()
for pkg in "${PKGS[@]}"; do
    if echo "${AVAILABLE}" | grep -qx "${pkg}"; then
        OFFICIAL+=("${pkg}")
    else
        AUR+=("${pkg}")
    fi
done

info "Installing ${#OFFICIAL[@]} official packages..."
if [ ${#OFFICIAL[@]} -gt 0 ]; then
    pacman -S --needed --noconfirm "${OFFICIAL[@]}" || warn "Some official packages failed to install"
fi
ok "Official packages done"

if [ ${#AUR[@]} -gt 0 ]; then
    info "Installing ${#AUR[@]} AUR packages: ${AUR[*]}"
    sudo -u builder yay -S --needed --noconfirm "${AUR[@]}" || warn "Some AUR packages failed to install"
    ok "AUR packages done"
fi

# =========================================================================
# Step 8: Deploy bin scripts
# =========================================================================
info "Step 8/14: Symlinking bin scripts to /usr/local/bin/..."
mkdir -p /usr/local/bin
for script in "${OMARCHY_DIR}"/bin/*; do
    chmod +x "${script}"
    ln -sf "${script}" /usr/local/bin/
done
ok "$(ls "${OMARCHY_DIR}"/bin/ | wc -l) scripts linked"

# =========================================================================
# Step 9: Deploy config files
# =========================================================================
info "Step 9/14: Deploying config files..."
mkdir -p "${HOME}/.config"
for item in "${OMARCHY_DIR}"/config/*; do
    name=$(basename "${item}")
    [[ "${name}" == "walker" ]] && continue
    cp -rf "${item}" "${HOME}/.config/"
done
ok "Config files deployed (walker skipped)"

# =========================================================================
# Step 10: Set up Neovim (LazyVim starter)
# =========================================================================
info "Step 10/14: Setting up Neovim..."
if [ ! -d "${HOME}/.config/nvim" ]; then
    git clone https://github.com/LazyVim/starter "${HOME}/.config/nvim"
    rm -rf "${HOME}/.config/nvim/.git"

    # Disable relative line numbers (omarchy default)
    mkdir -p "${HOME}/.config/nvim/lua/config"
    echo 'vim.opt.relativenumber = false' > "${HOME}/.config/nvim/lua/config/options.lua"

    ok "LazyVim starter installed"
else
    ok "Neovim config already exists"
fi

# =========================================================================
# Step 11: Environment -- WLR_ALLOW_ROOT for Hyprland as root
# =========================================================================
info "Step 11/14: Setting environment variables..."

# For UWSM/systemd user session
mkdir -p "${HOME}/.config/environment.d"
echo "WLR_ALLOW_ROOT=1" > "${HOME}/.config/environment.d/aarch64.conf"

# Also in hyprland.conf for belt-and-suspenders
if ! grep -q 'WLR_ALLOW_ROOT' "${HOME}/.config/hypr/hyprland.conf" 2>/dev/null; then
    printf '\n# aarch64: Allow Hyprland to run as root\nenv = WLR_ALLOW_ROOT,1\n' >> "${HOME}/.config/hypr/hyprland.conf"
fi
ok "WLR_ALLOW_ROOT=1 set"

# =========================================================================
# Step 12: Fuzzel keybinding (SUPER+Space replaces Walker)
# =========================================================================
info "Step 12/14: Adding fuzzel keybinding..."
BINDINGS="${HOME}/.config/hypr/bindings.conf"
if ! grep -q 'fuzzel' "${BINDINGS}" 2>/dev/null; then
    printf '\n# App launcher (fuzzel replaces walker on aarch64)\nunbind = SUPER, SPACE\nbindd = SUPER, SPACE, App launcher, exec, fuzzel\n' >> "${BINDINGS}"
fi
ok "SUPER+Space -> fuzzel"

# =========================================================================
# Step 13: SDDM (login manager + auto-login)
# =========================================================================
info "Step 13/14: Configuring SDDM..."

# Install omarchy SDDM theme
if [ -d "${OMARCHY_DIR}/default/sddm/omarchy" ]; then
    mkdir -p /usr/share/sddm/themes
    cp -rf "${OMARCHY_DIR}/default/sddm/omarchy" /usr/share/sddm/themes/
    ok "SDDM omarchy theme installed"
fi

# Auto-login config
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/omarchy.conf << 'SDDMCONF'
[Theme]
Current=omarchy

[Autologin]
User=root
Session=hyprland-uwsm
SDDMCONF

systemctl enable sddm 2>/dev/null || true
ok "SDDM configured (auto-login root -> hyprland-uwsm)"

# =========================================================================
# Step 14: Set Tokyo Night theme
# =========================================================================
info "Step 14/14: Setting Tokyo Night theme..."
THEME_DIR="${OMARCHY_DIR}/themes/tokyo-night"
if [ -d "${THEME_DIR}" ]; then
    # Create current theme symlink
    mkdir -p "${HOME}/.config/omarchy/current"
    ln -sf "${THEME_DIR}" "${HOME}/.config/omarchy/current/theme"

    # Set wallpaper
    WALLPAPER=$(ls "${THEME_DIR}/backgrounds/" 2>/dev/null | head -1)
    if [ -n "${WALLPAPER}" ]; then
        ln -sf "${THEME_DIR}/backgrounds/${WALLPAPER}" "${HOME}/.config/omarchy/current-background"
    fi

    # Try full theme setup (may partially fail without walker, non-fatal)
    export PATH="/usr/local/bin:${PATH}"
    omarchy-theme-set tokyo-night 2>/dev/null || warn "omarchy-theme-set had issues (non-fatal)"

    ok "Tokyo Night theme set"
else
    warn "Tokyo Night theme directory not found"
fi

# =========================================================================
# Enable system services
# =========================================================================
info "Enabling system services..."
for svc in docker bluetooth cups avahi-daemon; do
    systemctl enable "${svc}" 2>/dev/null && ok "Enabled ${svc}" || warn "Could not enable ${svc}"
done

# =========================================================================
# Done!
# =========================================================================
echo ""
echo "  Setup complete!"
echo ""
echo "  Reboot to start Omarchy:"
echo "    systemctl reboot"
echo ""

}

main "$@"
