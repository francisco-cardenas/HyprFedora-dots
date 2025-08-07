#!/bin/bash
# Configures LUKS decryption using YubiKey FIDO2 with systemd-cryptenroll on Fedora

set -euo pipefail

# Status print helpers
info() { echo -e "\e[1;34m[INFO]\e[0m $1"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m $1"; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $1"; }

# Show script purpose and ask for confirmation
echo -e "\e[1;36mThis script will:\e[0m
  - Configure dracut to include fido2 support
  - Enroll your YubiKey with a LUKS-encrypted volume using systemd-cryptenroll
  - Modify /etc/crypttab to enable FIDO2 unlocking
  - Regenerate the initramfs (dracut -f)

You will need to touch your YubiKey during enrollment.

\e[1;33mDo you want to proceed? (y/N)\e[0m"
read -r confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\e[1;31mAborted by user.\e[0m"
    exit 1
fi

# Ensure dracut includes fido2 module
info "Ensuring dracut includes fido2 module..."
echo 'add_dracutmodules+=" fido2 "' | sudo tee /etc/dracut.conf.d/fido2.conf > /dev/null

# Show available block devices
info "Listing available block devices:"
lsblk -o NAME,TYPE,SIZE,MOUNTPOINT

# Prompt user for encrypted LUKS device
echo ""
read -rp $'\e[1;36mEnter the full device path of your LUKS-encrypted partition (e.g. /dev/nvme0n1p3): \e[0m' luks_device

if [[ ! -b "$luks_device" ]]; then
    error "Device $luks_device does not exist or is not a block device."
    exit 1
fi

# Enroll the YubiKey with the selected LUKS device
info "Enrolling your YubiKey with $luks_device..."
sudo systemd-cryptenroll --fido2-device=auto "$luks_device"

# Update crypttab
info "Checking /etc/crypttab for update..."
crypttab="/etc/crypttab"
backup="/etc/crypttab.bak"

if [[ ! -f "$crypttab" ]]; then
    error "$crypttab not found. Manual configuration is required."
    exit 1
fi

# Count non-commented lines
entries=$(grep -v '^\s*#' "$crypttab" | grep -c .)

if [[ "$entries" -ne 1 ]]; then
    warn "Multiple entries in /etc/crypttab. Manual update recommended."
    echo "Example option to append: ,fido2-device=auto"
else
    # Ensure the last option is 'discard'
    if grep -v '^\s*#' "$crypttab" | grep -qE '\s+[^[:space:]]+\s+[^[:space:]]+\s+[^[:space:]]+\s+.*discard$'; then
        info "Single crypttab entry with 'discard' found. Attempting automatic update..."

        # Backup
        sudo cp -a "$crypttab" "$backup"
        info "Backed up original crypttab to $backup"

        # Append fido2-device=auto to discard
        sudo sed -i 's/\(discard\)\s*$/\1,fido2-device=auto/' "$crypttab"

        info "Updated /etc/crypttab to enable FIDO2 unlocking."
    else
        warn "Single entry detected, but it does not end with 'discard'."
        echo "Manual edit recommended. Example: add ',fido2-device=auto' to the options field."
    fi
fi

# Rebuild initramfs
info "Rebuilding initramfs with dracut..."
sudo dracut -f

# Reboot prompt
echo ""
info "Setup complete. A system reboot is required to test YubiKey unlocking at boot."
read -rp $'\e[1;33mDo you want to reboot now? (y/N): \e[0m' reboot_now
if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
    info "Rebooting system..."
    sudo reboot
else
    info "You chose not to reboot now. Please reboot manually later to test the setup."
fi

