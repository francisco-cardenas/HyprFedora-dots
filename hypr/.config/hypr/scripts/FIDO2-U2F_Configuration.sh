#!/bin/bash
# Configures YubiKey authentication on Fedora using pam-u2f

set -euo pipefail

# Display purpose and prompt user to continue
echo -e "\e[1;36mThis script will:\e[0m
  - Install required packages for YubiKey PAM authentication
  - Detect and configure a YubiKey using FIDO2
  - Register your YubiKey with pam-u2f
  - Save your credentials in ~/.config/Yubico/u2f_keys
  - Configure your system's authselect profile to use pam-u2f

You will be prompted to touch your YubiKey during the process.

\e[1;33mDo you want to proceed? (y/N)\e[0m"
read -r confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\e[1;31mAborted by user.\e[0m"
    exit 1
fi

# Status print helpers
info() { echo -e "\e[1;34m[INFO]\e[0m $1"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m $1"; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $1"; }

# Ensure required packages are installed
info "Installing required packages..."
sudo dnf install -y pam-u2f pamu2fcfg fido2-tools

# Detect FIDO2 device
info "Detecting YubiKey (FIDO2 device)..."
fido_output=$(fido2-token -L 2>/dev/null || true)
if [[ -z "$fido_output" ]]; then
    error "No FIDO2 device found. Please insert your YubiKey and try again."
    exit 1
fi

echo "$fido_output"
device_path=$(echo "$fido_output" | grep -o '/dev/hidraw[0-9]*' | head -n1)

if [[ -z "$device_path" ]]; then
    error "Failed to extract device path."
    exit 1
fi

info "Found YubiKey at $device_path"

# Optionally configure the device
info "Initializing YubiKey for use (this is safe to rerun)..."
sudo fido2-token -C "$device_path"

# Generate the U2F key mapping
config_dir="$HOME/.config/Yubico"
mkdir -p "$config_dir"
u2f_file="$config_dir/u2f_keys"

info "Touch your YubiKey when prompted to complete registration..."
pamu2fcfg --pin-verification > "$u2f_file"

info "U2F keys saved to $u2f_file"

# Configure authselect
info "Checking authselect profile..."
authselect_output=$(authselect current 2>/dev/null || true)

if echo "$authselect_output" | grep -q "Profile ID: local"; then
    info "Using local profile. Adding pam-u2f module..."

    options=$(echo "$authselect_output" | grep "with-" | awk '{$1=""; print $0}' | xargs)
    new_options="$options with-pam-u2f"

    info "Applying new authselect options: $new_options"
    sudo authselect select local $new_options

else
    warn "Your current authselect profile is not local:"
    echo "$authselect_output"
    echo ""
    warn "To continue, you'll need to review your authselect configuration manually."
    echo "Suggested command:"
    echo "  sudo authselect select sssd $(echo $authselect_output | grep 'with-' | awk '{print $NF}' | xargs) with-pam-u2f"
fi

info "YubiKey PAM authentication setup complete."

