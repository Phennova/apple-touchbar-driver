#!/bin/bash
# install.sh - Install Apple Touch Bar driver for T1 MacBook Pro on Arch Linux
#
# Prerequisites: dkms, linux-headers (for your running kernel)
# Tested on: kernel 6.19.11-arch1-1, 6.18.22-1-lts
set -euo pipefail

DKMS_NAME="apple-touchbar"
DKMS_VER="0.4"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo $0)"
    exit 1
fi

echo "=== Apple Touch Bar Driver Installer ==="
echo ""

# --- Step 1: Safety check - remove from mkinitcpio if present ---
echo "[1/6] Checking mkinitcpio.conf..."
if grep -qE 'MODULES=.*apple_ib' /etc/mkinitcpio.conf 2>/dev/null; then
    echo "  WARNING: Found apple_ib modules in /etc/mkinitcpio.conf MODULES."
    echo "  This causes boot failures. Removing them..."
    cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
    sed -i 's/apple_ib_tb//g; s/apple_ib_als//g; s/apple_ibridge//g' /etc/mkinitcpio.conf
    # Clean up extra spaces/commas that might result
    sed -i 's/  */ /g; s/( /(/; s/ )/)/; s/(  *)/()/' /etc/mkinitcpio.conf
    echo "  Removed. Backup saved to /etc/mkinitcpio.conf.bak"
    echo "  Rebuilding initramfs..."
    mkinitcpio -P
    echo "  Done."
else
    echo "  OK - no apple modules in mkinitcpio MODULES."
fi

# --- Step 2: Remove old DKMS module if present ---
echo ""
echo "[2/6] Checking for existing DKMS installation..."
# Remove any previous version of apple-touchbar (supports clean upgrades)
while IFS= read -r old_ver; do
    [ -z "$old_ver" ] && continue
    echo "  Removing $DKMS_NAME/$old_ver..."
    dkms remove "$DKMS_NAME/$old_ver" --all 2>/dev/null || true
    rm -rf "/usr/src/${DKMS_NAME}-${old_ver}"
done < <(dkms status "$DKMS_NAME" 2>/dev/null | awk -F'[/,:]' '/^'"$DKMS_NAME"'/ {print $2}' | sort -u)

# Also remove the old "applespi" DKMS package if present (from Heratiki's original)
if dkms status "applespi" 2>/dev/null | grep -q "applespi"; then
    echo "  Removing old applespi DKMS package..."
    dkms remove "applespi/0.1" --all 2>/dev/null || true
fi
echo "  Done."

# --- Step 3: Install DKMS source ---
echo ""
echo "[3/6] Installing DKMS source..."
DKMS_DEST="/usr/src/${DKMS_NAME}-${DKMS_VER}"
rm -rf "$DKMS_DEST"
mkdir -p "$DKMS_DEST"
cp "$SRC_DIR"/apple-ibridge.c "$DKMS_DEST/"
cp "$SRC_DIR"/apple-ibridge.h "$DKMS_DEST/"
cp "$SRC_DIR"/apple-ib-tb.c "$DKMS_DEST/"
cp "$SRC_DIR"/apple-ib-als.c "$DKMS_DEST/"
cp "$SRC_DIR"/Makefile "$DKMS_DEST/"
cp "$SRC_DIR"/dkms.conf "$DKMS_DEST/"
echo "  Installed to $DKMS_DEST"

# --- Step 4: Build and install DKMS modules ---
echo ""
echo "[4/6] Building modules with DKMS..."
dkms add "$DKMS_NAME/$DKMS_VER"

# Build for all installed kernels that have headers
for KVER in /lib/modules/*/build; do
    KVER=$(basename "$(dirname "$KVER")")
    echo "  Building for kernel $KVER..."
    if dkms build "$DKMS_NAME/$DKMS_VER" -k "$KVER"; then
        dkms install "$DKMS_NAME/$DKMS_VER" -k "$KVER"
        echo "  Installed for $KVER"
    else
        echo "  WARNING: Build failed for $KVER (may be ok if you don't use this kernel)"
    fi
done

# --- Step 5: Install config files ---
echo ""
echo "[5/6] Installing configuration files..."

# modprobe config
cp "$SRC_DIR/config/apple-touchbar.conf" /etc/modprobe.d/apple-touchbar.conf
echo "  Installed /etc/modprobe.d/apple-touchbar.conf"

# USB rebind script
cp "$SRC_DIR/config/apple-touchbar-rebind" /usr/local/bin/apple-touchbar-rebind
chmod 755 /usr/local/bin/apple-touchbar-rebind
echo "  Installed /usr/local/bin/apple-touchbar-rebind"

# Diagnostic script
cp "$SRC_DIR/config/apple-touchbar-diagnose" /usr/local/bin/apple-touchbar-diagnose
chmod 755 /usr/local/bin/apple-touchbar-diagnose
echo "  Installed /usr/local/bin/apple-touchbar-diagnose"

# udev rule to prevent hid-sensor-hub from stealing iBridge interfaces
cp "$SRC_DIR/config/99-apple-touchbar.rules" /etc/udev/rules.d/99-apple-touchbar.rules
udevadm control --reload-rules 2>/dev/null || true
echo "  Installed /etc/udev/rules.d/99-apple-touchbar.rules"

# Check for usbmuxd — its udev rules match 05ac:8600 due to historical PID
# overlap and WILL steal the iBridge if installed and active.
if command -v usbmuxd >/dev/null 2>&1; then
    if systemctl is-active usbmuxd >/dev/null 2>&1; then
        echo "  WARNING: usbmuxd is running. Its udev rules may steal the iBridge."
        echo "           If Touch Bar doesn't activate, disable usbmuxd with:"
        echo "             sudo systemctl disable --now usbmuxd.service"
    fi
    for rules_file in /usr/lib/udev/rules.d/*usbmuxd* /etc/udev/rules.d/*usbmuxd*; do
        [ -f "$rules_file" ] || continue
        if grep -q '8600' "$rules_file" 2>/dev/null; then
            echo "  WARNING: $rules_file contains a match for 05ac:8600 (iBridge)."
            echo "           This will conflict. Consider editing out the 8600 match."
        fi
    done
fi

# systemd services
cp "$SRC_DIR/config/apple-touchbar.service" /etc/systemd/system/apple-touchbar.service
cp "$SRC_DIR/config/apple-touchbar-resume.service" /etc/systemd/system/apple-touchbar-resume.service
echo "  Installed systemd services"

# --- Step 6: Enable services ---
echo ""
echo "[6/6] Enabling systemd services..."
systemctl daemon-reload
systemctl enable apple-touchbar.service
systemctl enable apple-touchbar-resume.service
echo "  Done."

echo ""
echo "=== Installation Complete ==="
echo ""
echo "To activate the Touch Bar NOW (without rebooting):"
echo "  sudo systemctl start apple-touchbar.service"
echo ""
echo "The Touch Bar will activate automatically on future boots."
echo ""
echo "Useful commands:"
echo "  - Check status:    systemctl status apple-touchbar.service"
echo "  - View logs:       journalctl -u apple-touchbar.service"
echo "  - Manual rebind:   sudo apple-touchbar-rebind"
echo "  - Diagnostic dump: sudo apple-touchbar-diagnose"
echo "  - Change fn mode:  echo 1 | sudo tee /sys/class/platform/apple-ib-tb.0/fnmode"
echo "    (0=fkeys, 1=fn-switches, 2=inverse, 3=special-only)"
echo "  - Idle timeout:    echo 300 | sudo tee /sys/class/platform/apple-ib-tb.0/idle_timeout"
echo ""
