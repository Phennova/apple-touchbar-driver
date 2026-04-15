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
3. **Install DKMS source** to `/usr/src/apple-touchbar-<version>/`
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

## Post-Install: Make the Keys Actually Do Things

Once the driver is working, the Touch Bar's special keys emit standard Linux media keycodes (`XF86AudioRaiseVolume`, `XF86MonBrightnessUp`, etc.). **But Linux does not handle media keys automatically** — your desktop environment or window manager has to bind them to actions.

### Required helper tools

```bash
sudo pacman -S wireplumber playerctl brightnessctl
```

### Find your keyboard backlight LED name

Your keyboard backlight is a separate LED device, not part of the Touch Bar driver. The exact sysfs name varies by model. Find it with:

```bash
ls /sys/class/leds/ | grep -i -E 'kbd|keyboard'
```

Common names:
- `smc::kbd_backlight` (Intel Macs with `applesmc`)
- `apple::kbd_backlight`
- `kbd_backlight`

If nothing shows up, you're missing the `applesmc` module:

```bash
sudo modprobe applesmc
# Make it load at boot
echo applesmc | sudo tee /etc/modules-load.d/applesmc.conf
```

Test manually (replace `smc::kbd_backlight` with whatever you found):

```bash
# Turn backlight fully on
echo 255 | sudo tee /sys/class/leds/smc::kbd_backlight/brightness

# Read max value
cat /sys/class/leds/smc::kbd_backlight/max_brightness
```

### Hyprland (Wayland)

Add to `~/.config/hypr/hyprland.conf` (replace `smc::kbd_backlight` with your actual device):

```ini
# --- Touch Bar / media key bindings ---
# Volume
bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindl  = , XF86AudioMute,        exec, wpctl set-mute   @DEFAULT_AUDIO_SINK@ toggle

# Media playback
bindl = , XF86AudioPlay, exec, playerctl play-pause
bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPrev, exec, playerctl previous

# Screen brightness
bindel = , XF86MonBrightnessUp,   exec, brightnessctl set 5%+
bindel = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

# Keyboard backlight (replace smc::kbd_backlight with your device name)
bindel = , XF86KbdBrightnessUp,   exec, brightnessctl -d smc::kbd_backlight set 10%+
bindel = , XF86KbdBrightnessDown, exec, brightnessctl -d smc::kbd_backlight set 10%-
```

Reload: `hyprctl reload`.

### Sway (Wayland)

Add to `~/.config/sway/config`:

```
bindsym --locked XF86AudioRaiseVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bindsym --locked XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym --locked XF86AudioMute        exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindsym --locked XF86AudioPlay        exec playerctl play-pause
bindsym --locked XF86AudioNext        exec playerctl next
bindsym --locked XF86AudioPrev        exec playerctl previous
bindsym --locked XF86MonBrightnessUp   exec brightnessctl set 5%+
bindsym --locked XF86MonBrightnessDown exec brightnessctl set 5%-
bindsym --locked XF86KbdBrightnessUp   exec brightnessctl -d smc::kbd_backlight set 10%+
bindsym --locked XF86KbdBrightnessDown exec brightnessctl -d smc::kbd_backlight set 10%-
```

### i3 (X11)

Add to `~/.config/i3/config`:

```
bindsym XF86AudioRaiseVolume exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bindsym XF86AudioLowerVolume exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym XF86AudioMute        exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindsym XF86AudioPlay        exec --no-startup-id playerctl play-pause
bindsym XF86AudioNext        exec --no-startup-id playerctl next
bindsym XF86AudioPrev        exec --no-startup-id playerctl previous
bindsym XF86MonBrightnessUp   exec --no-startup-id brightnessctl set 5%+
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 5%-
bindsym XF86KbdBrightnessUp   exec --no-startup-id brightnessctl -d smc::kbd_backlight set 10%+
bindsym XF86KbdBrightnessDown exec --no-startup-id brightnessctl -d smc::kbd_backlight set 10%-
```

### GNOME / KDE Plasma

Media keys work out of the box. If they don't, check the DE's keyboard settings — `XF86AudioRaiseVolume` / `XF86MonBrightnessUp` should already be bound.

### Why this is needed

On Wayland, keys the compositor doesn't bind "fall through" to the focused application. Terminals show unknown media keycodes as escape sequences (which looks like "439u" or similar — that's the compositor printing the keycode as raw text). Once the compositor binds the key, it's consumed before reaching any application, and the bound command actually runs.

## Uninstallation

```bash
cd apple-touchbar-driver
sudo ./uninstall.sh
```

This removes the DKMS modules, systemd services, config files, and the rebind script.

## Level 2: Custom Rendering (experimental, in progress)

Level 2 adds support for rendering **custom icons and actions** to the Touch Bar, like macOS does. Fn-hold swaps the display to F1–F12. It's being built out in increments — pull the latest commit, re-run `sudo ./install.sh`, and you'll be on the next increment.

### Increment 1 — `mac_mode` config switch (CURRENT)

Adds a module parameter that switches the iBridge to USB Configuration 2 ("OS X mode"), which exposes the Touch Bar as a raw framebuffer. No rendering yet — the Touch Bar will go **blank** in this mode, because Level 1's predefined layouts don't exist here. This increment exists to verify Config 2 works on your hardware before we commit to it.

**To test:**

```bash
# Load the module with mac_mode=1
sudo modprobe -r apple-ib-tb apple-ib-als apple-ibridge
sudo modprobe apple-ibridge mac_mode=1
sudo apple-touchbar-rebind

# Verify the device is now in config 2
lsusb -d 05ac:8600 -v 2>/dev/null | grep bConfigurationValue
# Should show: bConfigurationValue  2

# You should now see additional interfaces, including a USB class 10 (AV):
lsusb -d 05ac:8600 -v 2>/dev/null | grep -E 'bInterfaceClass|bInterfaceNumber'
```

**To revert to Level 1:**

```bash
sudo modprobe -r apple-ib-tb apple-ib-als apple-ibridge
sudo systemctl restart apple-touchbar.service
```

### Increment 2 — `appletbdrm-t1` kernel module (upcoming)

Will vendor the mainline kernel's `appletbdrm.c` (currently only matches T2 ID `0x8302`) and patch in the T1 ID `0x8600`. Once loaded with `mac_mode=1`, a `/dev/dri/cardN` device appears for the Touch Bar and arbitrary pixels can be drawn to it.

### Increment 3 — `tiny-dfr` renderer (upcoming)

Installs [tiny-dfr](https://github.com/AsahiLinux/tiny-dfr) (Asahi Linux's userspace Touch Bar renderer), udev rules for the multi-touch digitizer, and a default config that reproduces F1–F12 with Fn-toggle behavior. From there you edit `/etc/tiny-dfr/config.toml` to add custom icons, labels, and key bindings.

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

For a full state dump:

```bash
sudo apple-touchbar-diagnose
```

### Keyboard backlight doesn't work

The keyboard backlight is NOT handled by this driver — it's a separate LED controlled by the `applesmc` kernel module.

Check if the LED device exists:

```bash
ls /sys/class/leds/ | grep -i kbd
```

If nothing appears, load `applesmc`:

```bash
sudo modprobe applesmc
echo applesmc | sudo tee /etc/modules-load.d/applesmc.conf
ls /sys/class/leds/  # should now show smc::kbd_backlight or similar
```

Test manually:

```bash
# Replace smc::kbd_backlight with whatever `ls` showed
cat /sys/class/leds/smc::kbd_backlight/max_brightness
echo 128 | sudo tee /sys/class/leds/smc::kbd_backlight/brightness
```

If that works but pressing F5/F6 on the Touch Bar does nothing, your compositor has no binding for `XF86KbdBrightnessUp` / `XF86KbdBrightnessDown` — see **Post-Install: Make the Keys Actually Do Things** above.

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
