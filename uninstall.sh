#!/bin/bash
# uninstall.sh - Remove Apple Touch Bar driver
set -euo pipefail

DKMS_NAME="apple-touchbar"
DKMS_VER="0.2"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo $0)"
    exit 1
fi

echo "=== Apple Touch Bar Driver Uninstaller ==="
echo ""

# Stop and disable services
echo "[1/4] Stopping services..."
systemctl stop apple-touchbar.service 2>/dev/null || true
systemctl stop apple-touchbar-resume.service 2>/dev/null || true
systemctl disable apple-touchbar.service 2>/dev/null || true
systemctl disable apple-touchbar-resume.service 2>/dev/null || true

# Unload modules
echo "[2/4] Unloading modules..."
modprobe -r apple-ib-als 2>/dev/null || true
modprobe -r apple-ib-tb 2>/dev/null || true
modprobe -r apple-ibridge 2>/dev/null || true

# Remove DKMS
echo "[3/4] Removing DKMS modules..."
dkms remove "$DKMS_NAME/$DKMS_VER" --all 2>/dev/null || true
rm -rf "/usr/src/${DKMS_NAME}-${DKMS_VER}"

# Remove config files
echo "[4/4] Removing config files..."
rm -f /etc/modprobe.d/apple-touchbar.conf
rm -f /usr/local/bin/apple-touchbar-rebind
rm -f /etc/systemd/system/apple-touchbar.service
rm -f /etc/systemd/system/apple-touchbar-resume.service
systemctl daemon-reload

echo ""
echo "=== Uninstall complete ==="
