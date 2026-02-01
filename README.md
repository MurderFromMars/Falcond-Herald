# Falcond Herald

A notification companion for [Falcond](https://github.com/nowrep/falcond) that announces power profile changes via desktop notifications.

## What It Does

Falcond Herald watches for power profile changes made by Falcond (or any other source) and displays themed desktop notifications to keep you informed.

| Profile | Notification |
|---------|--------------|
| ⚡ Performance | "Performance Optimization Activated" |
| 🔋 Balanced | "Resuming standard desktop power profile" |
| 🍃 Power-saver | "Power conservation mode engaged" |

## Compatibility

### Supported Backends
- **power-profiles-daemon** - Standard on most distros
- **tuned-ppd** - Fedora/RHEL compatibility layer for tuned

Both expose the same D-Bus interface (`net.hadess.PowerProfiles`), so Herald works identically with either.

### Supported Desktop Environments
Works with **any DE or WM** that has a notification daemon:

| Environment | Notification Daemon |
|-------------|---------------------|
| KDE Plasma | Built-in |
| GNOME | Built-in |
| XFCE | xfce4-notifyd |
| Cinnamon | Built-in |
| MATE | mate-notification-daemon |
| LXQt | lxqt-notificationd |
| Hyprland | mako, dunst, swaync |
| Sway | mako, dunst, swaync |
| i3 | dunst |
| bspwm | dunst |

## Requirements

- `power-profiles-daemon` OR `tuned-ppd`
- `python3`
- `python3-dbus` / `python-dbus`
- `python3-gi` / `python-gobject`
- `libnotify` / `notify-send`

### Installing Dependencies

**Arch Linux:**
```bash
sudo pacman -S power-profiles-daemon python-dbus python-gobject libnotify
sudo systemctl enable --now power-profiles-daemon
```

**Debian/Ubuntu:**
```bash
sudo apt install power-profiles-daemon python3-dbus python3-gi libnotify-bin
sudo systemctl enable --now power-profiles-daemon
```

**Fedora (power-profiles-daemon):**
```bash
sudo dnf install power-profiles-daemon python3-dbus python3-gobject libnotify
sudo systemctl enable --now power-profiles-daemon
```

**Fedora (tuned-ppd alternative):**
```bash
sudo dnf install tuned-ppd python3-dbus python3-gobject libnotify
sudo systemctl enable --now tuned-ppd
```

## Installation

**One-liner:**
```
curl -fsSL https://raw.githubusercontent.com/MurderFromMars/Falcond-Herald/main/install.sh | bash
```

**Manual:**
```bash
git clone https://github.com/MurderFromMars/Falcond-Herald.git
cd Falcond-Herald
sh install.sh
```

## Uninstallation

```bash
./uninstall.sh
```

## Service Commands

```bash
# Check status
systemctl --user status falcond-herald

# View logs
journalctl --user -u falcond-herald -f

# Restart
systemctl --user restart falcond-herald

# Stop
systemctl --user stop falcond-herald
```

## Customization

Edit `~/.local/bin/falcond-herald` to customize notification messages:

```python
PROFILES = {
    "performance": {
        "title": "⚡ Falcond Herald",
        "message": "Performance Optimization Activated",
        "icon": "power-profile-performance-symbolic",
        "urgency": "normal"
    },
    # ... customize as desired
}
```

## How It Works

Falcond Herald subscribes to D-Bus property change signals from the `net.hadess.PowerProfiles` interface. This interface is provided by either `power-profiles-daemon` or `tuned-ppd`. When the `ActiveProfile` property changes (whether by Falcond, manual command, or GUI), it sends a notification via `notify-send`.

The daemon runs as a systemd user service:
- Auto-starts on login
- Zero CPU usage until a profile change occurs
- Works on both X11 and Wayland

## License

MIT License
