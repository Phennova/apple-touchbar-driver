# Apple Touch Bar Driver for Linux (T1 Chip — 2016/2017 MacBook Pro)

Kernel driver and installation tooling for the Touch Bar on **T1-chip MacBook Pros** running Linux. Provides function keys, special keys (brightness, volume, etc.), Fn key toggling, idle dimming, and ambient light sensor support.

## Supported Hardware

| Model | Identifier | Chip | Status |
|---|---|---|---|
| MacBook Pro 13" 2016 (Touch Bar) | MacBookPro13,2 | T1 | Supported |
| MacBook Pro 15" 2016 (Touch Bar) | MacBookPro13,3 | T1 | Supported |
| MacBook Pro 13" 2017 (Touch Bar) | MacBookPro14,2 | T1 | Supported |
| MacBook Pro 15" 2017 (Touch Bar) | MacBookPro14,3 | T1 | Supported |

> **Note:** This driver is for **T1 chip** MacBooks only (2016–2017). If you have a 2018+ MacBook Pro (T2 chip), you need the [t2linux](https://wiki.t2linux.org/) project instead. The upstream kernel drivers merged in 6.15 are also T2-only and do not help T1 Macs.

## Tested Kernels

- `6.19.11-arch1-1` (Arch Linux mainline)
- `6.18.22-1-lts` (Arch Linux LTS)

Should work on any kernel **6.11+** thanks to version-guarded API compatibility. Older kernels (5.x, 6.0–6.10) should also work but are untested with this packaging.

## How It Works

The T1 chip exposes the Touch Bar as a USB device (vendor `05ac`, product `8600`) through the Apple iBridge interface. The driver consists of three kernel modules:

| Module | Purpose |
|---|---|
| `apple-ibridge` | HID multiplexer for the iBridge USB device. The T1 exposes both Touch Bar and ALS reports on shared HID interfaces — this module creates virtual child HID devices so each sub-driver can attach independently. |
| `apple-ib-tb` | Touch Bar control — switches between ESC-only, function keys, and special keys (brightness, volume, media). Handles Fn key toggling, idle timeout, display dimming, and key translation. |
| `apple-ib-als` | Ambient light sensor — exposes illuminance readings via the IIO subsystem. |

### Why not just `modprobe`?

The iBridge USB device is already claimed by the generic HID driver by the time userspace loads modules. The driver must be loaded, then the USB device must be **unbound and rebound** so the `apple-ibridge` HID driver can claim it. The included systemd service and rebind script handle this automatically.

### The hid-sensor-hub race condition

The kernel's built-in `hid-sensor-hub` driver matches HID devices with sensor usage pages. The iBridge exposes two HID interfaces — one for the keyboard/Touch Bar mode control, and one for display brightness and the ambient light sensor. Without intervention, `hid-sensor-hub` claims the second interface before `apple-ibridge` can, and the Touch Bar never activates (it needs both interfaces). The included udev rule and rebind script prevent this by evicting `hid-sensor-hub` from iBridge devices.

### Why not load via mkinitcpio/initramfs?

**Do not add these modules to `MODULES` in `/etc/mkinitcpio.conf`.** Loading them in the initramfs (before USB enumeration completes) interferes with root device discovery and will prevent your system from booting. The install script checks for this and removes them if found.

## Prerequisites

```bash
sudo pacman -S dkms linux-headers
# If you run the LTS kernel too:
sudo pacman -S linux-lts-headers
```

## Installation

```bash
git clone https://github.com/Phennova/apple-touchbar-driver.git
cd apple-touchbar-driver
sudo ./install.sh
```

The install script will:

1. **Check `/etc/mkinitcpio.conf`** — removes any apple-ib modules from `MODULES` and rebuilds initramfs if needed (prevents the boot crash described above)
2. **Remove old DKMS installations** — cleans up previous versions, including the old `applespi` DKMS package
3. **Install DKMS source** to `/usr/src/apple-touchbar-0.2/`
4. **Build kernel modules** for every installed kernel that has headers
5. **Install config files** — modprobe dependency ordering, USB rebind script, systemd services
6. **Enable systemd services** — auto-start on boot and reactivation after suspend/resume

### Activate immediately (no reboot needed)

```bash
sudo systemctl start apple-touchbar.service
```

### Verify it's working

```bash
# Check service status
systemctl status apple-touchbar.service

# Check kernel log for Touch Bar messages
dmesg | grep -i -E 'apple|ibridge|touchbar'

# You should see something like:
#   apple-ibridge: registered driver 'apple-ib-touchbar'
#   apple-ib-tb: Touchbar activated
```

## Configuration

### Fn Key Mode

Controls what the Touch Bar shows by default and what happens when you press Fn:

```bash
# Read current mode
cat /sys/bus/platform/devices/apple-ib-tb.*/fnmode

# Set mode (takes effect immediately)
echo 1 | sudo tee /sys/bus/platform/devices/apple-ib-tb.*/fnmode
```

| Value | Behavior |
|---|---|
| `0` | Always show function keys (F1–F12) |
| `1` | Show special keys; Fn switches to F1–F12 **(default)** |
| `2` | Show F1–F12; Fn switches to special keys |
| `3` | Always show special keys (brightness, volume, etc.) |

### Idle Timeout

Controls when the Touch Bar display turns off after no input:

```bash
# Set to 5 minutes (300 seconds)
echo 300 | sudo tee /sys/bus/platform/devices/apple-ib-tb.*/idle_timeout

# Never turn off
echo -1 | sudo tee /sys/bus/platform/devices/apple-ib-tb.*/idle_timeout

# Disable Touch Bar completely
echo -2 | sudo tee /sys/bus/platform/devices/apple-ib-tb.*/idle_timeout
```

### Dim Timeout

Controls when the Touch Bar dims before turning off:

```bash
# Dim after 60 seconds of no input
echo 60 | sudo tee /sys/bus/platform/devices/apple-ib-tb.*/dim_timeout

# Auto-calculate based on idle timeout (default)
echo -2 | sudo tee /sys/bus/platform/devices/apple-ib-tb.*/dim_timeout
```

### Persist Settings Across Reboots

Edit `/etc/modprobe.d/apple-touchbar.conf` and uncomment/modify the options line:

```
options apple-ib-tb idle_timeout=300 dim_timeout=-2 fnmode=1
```

## Uninstallation

```bash
cd apple-touchbar-driver
sudo ./uninstall.sh
```

This removes the DKMS modules, systemd services, config files, and the rebind script.

## Troubleshooting

### Touch Bar not responding after boot

Check if the systemd service ran successfully:

```bash
systemctl status apple-touchbar.service
journalctl -u apple-touchbar.service
```

If the rebind failed, try manually:

```bash
sudo apple-touchbar-rebind
```

### Touch Bar not working after suspend/resume

The resume service should handle this automatically. Check:

```bash
journalctl -u apple-touchbar-resume.service
```

If needed, manually rebind:

```bash
sudo apple-touchbar-rebind
```

### DKMS build fails after kernel update

Make sure you have the headers for your new kernel:

```bash
# For mainline kernel
sudo pacman -S linux-headers

# For LTS kernel
sudo pacman -S linux-lts-headers

# Rebuild
sudo dkms autoinstall
```

### System fails to boot (added modules to mkinitcpio)

If you accidentally added apple modules to `/etc/mkinitcpio.conf` and can't boot:

1. Boot from an Arch Linux USB
2. Mount your root partition
3. Edit `mnt/etc/mkinitcpio.conf` — remove `apple_ibridge`, `apple_ib_tb`, `apple_ib_als` from `MODULES=()`
4. `arch-chroot /mnt mkinitcpio -P`
5. Reboot

### Module loads but Touch Bar shows nothing

The iBridge might need a power cycle. Try:

```bash
sudo modprobe -r apple-ib-tb apple-ib-als apple-ibridge
sudo apple-touchbar-rebind
sudo modprobe apple-ibridge
sudo modprobe apple-ib-tb
sudo modprobe apple-ib-als
sudo apple-touchbar-rebind
```

### Finding your MacBook model

```bash
sudo dmidecode -s system-product-name
# e.g., "MacBookPro13,3"
```

## File Layout

```
apple-touchbar-driver/
├── apple-ibridge.c          # iBridge USB/HID multiplexer
├── apple-ibridge.h          # Shared header
├── apple-ib-tb.c            # Touch Bar sub-driver
├── apple-ib-als.c           # Ambient Light Sensor sub-driver
├── Makefile                  # Kernel module build
├── dkms.conf                # DKMS configuration
├── config/
│   ├── apple-touchbar.conf           # modprobe dependency config
│   ├── apple-touchbar.service        # systemd: load modules on boot
│   ├── apple-touchbar-resume.service # systemd: rebind after suspend
│   ├── apple-touchbar-rebind         # script: find & rebind iBridge USB
│   └── 99-apple-touchbar.rules      # udev: block hid-sensor-hub on iBridge
├── install.sh                # One-command installer
├── uninstall.sh              # Clean uninstaller
└── LICENSE                   # GPL v2
```

## Credits

The kernel driver code originates from [Ronald Tschalär's macbook12-spi-driver](https://github.com/roadrunner2/macbook12-spi-driver), with kernel API fixes from [Heratiki's fork](https://github.com/Heratiki/macbook12-spi-driver) and the [t2linux community](https://github.com/t2linux/apple-ib-drv). This repository adds proper installation tooling, systemd integration, dynamic USB rebinding, and suspend/resume support for a working out-of-the-box experience on modern kernels.

## License

GPL v2 — see [LICENSE](LICENSE).
