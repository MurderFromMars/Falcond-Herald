#!/bin/bash
#
# Falcond Herald Self-Contained Installer
# This script embeds all necessary files and can be run via curl | bash
#

set -e

BIN_DIR="$HOME/.local/bin"
SERVICE_DIR="$HOME/.config/systemd/user"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${CYAN}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Falcond Herald                  ║${NC}"
echo -e "${CYAN}║    Power Profile Notification Daemon      ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# Check for required dependencies
print_status "Checking dependencies..."

MISSING_DEPS=()

# Check Python
if ! command -v python3 &> /dev/null; then
    MISSING_DEPS+=("python3")
fi

# Check for python dbus module
if ! python3 -c "import dbus" 2>/dev/null; then
    MISSING_DEPS+=("python3-dbus / python-dbus")
fi

# Check for python gi module
if ! python3 -c "from gi.repository import GLib" 2>/dev/null; then
    MISSING_DEPS+=("python3-gi / python-gobject")
fi

# Check for notify-send
if ! command -v notify-send &> /dev/null; then
    MISSING_DEPS+=("libnotify / libnotify-bin")
fi

# Check for power-profiles-daemon OR tuned-ppd
PPD_RUNNING=false
if systemctl is-active --quiet power-profiles-daemon 2>/dev/null; then
    PPD_RUNNING=true
    print_success "Found: power-profiles-daemon"
elif systemctl is-active --quiet tuned-ppd 2>/dev/null; then
    PPD_RUNNING=true
    print_success "Found: tuned-ppd"
fi

if [ "$PPD_RUNNING" = false ]; then
    print_warning "No power profile daemon is running"
    echo ""
    echo "Please install ONE of the following:"
    echo ""
    echo "  power-profiles-daemon (recommended):"
    echo "    Arch:          sudo pacman -S power-profiles-daemon"
    echo "    Debian/Ubuntu: sudo apt install power-profiles-daemon"
    echo "    Fedora:        sudo dnf install power-profiles-daemon"
    echo ""
    echo "  tuned-ppd (Fedora/RHEL alternative):"
    echo "    Fedora:        sudo dnf install tuned-ppd"
    echo ""
    echo "Then enable: sudo systemctl enable --now <service-name>"
    echo ""
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    print_error "Missing dependencies:"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Install on Arch:          sudo pacman -S python-dbus python-gobject libnotify"
    echo "Install on Debian/Ubuntu: sudo apt install python3-dbus python3-gi libnotify-bin"
    echo "Install on Fedora:        sudo dnf install python3-dbus python3-gobject libnotify"
    echo ""
    exit 1
fi

print_success "All dependencies satisfied"

# Create directories
print_status "Creating directories..."
mkdir -p "$BIN_DIR"
mkdir -p "$SERVICE_DIR"

# Create the daemon script
print_status "Installing falcond-herald to $BIN_DIR..."
cat > "$BIN_DIR/falcond-herald" << 'HERALD_SCRIPT_EOF'
#!/usr/bin/env python3

####A companion service that announces Falcond's power profile changes.




import os
import sys
import signal
import subprocess
from pathlib import Path

try:
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    # Import Notify for advanced notification control
    from gi.repository import GLib, Notify
except ImportError as e:
    print(f"Error: Missing dependency - {e}")
    print("Please install: python3-dbus python3-gi libnotify")
    sys.exit(1)


# Notification Configuration
PROFILES = {
    "performance": {
        "title": "Falcond",
        "message": "Performance Optimizations Active",
        "icon": "weather-storm-symbolic"  # Lightning bolt (fallback: input-gaming-symbolic)
    },
    "balanced": {
        "title": "Falcond",
        "message": "Standard Performance Restored",
        "icon": "emblem-default-symbolic" # Checkmark/Standard (fallback: user-available-symbolic)
    },
    "power-saver": {
        "title": "Falcond",
        "message": "Low Power Mode Active.",
        "icon": "night-light-symbolic"    # Moon/Night (fallback: battery-low-symbolic)
    }
}

# D-Bus constants
PPD_BUS_NAME = "net.hadess.PowerProfiles"
PPD_OBJECT_PATH = "/net/hadess/PowerProfiles"
PPD_INTERFACE = "net.hadess.PowerProfiles"
DBUS_PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"


class FalcondHerald:
    def __init__(self):
        self.loop = None
        self.bus = None
        self.current_profile = None
        self.first_run = True

        # 1. SETUP ENVIRONMENT
        self._setup_environment()

        # 2. INIT NOTIFICATION SYSTEM
        try:
            if not Notify.init("Falcond"):
                print("Warning: Failed to initialize libnotify")
        except Exception as e:
            print(f"Warning: Notify init error: {e}")

    def _setup_environment(self):
        """Ensure the process has the environment variables needed to talk to the display."""
        if "DISPLAY" not in os.environ and "WAYLAND_DISPLAY" not in os.environ:
            os.environ["DISPLAY"] = ":0"

        if "XDG_RUNTIME_DIR" not in os.environ:
            uid = os.getuid()
            runtime_dir = f"/run/user/{uid}"
            if os.path.exists(runtime_dir):
                os.environ["XDG_RUNTIME_DIR"] = runtime_dir

    def send_notification(self, profile: str) -> None:
        """
        Send a Critical notification that auto-closes.
        """
        config = PROFILES.get(profile, {
            "title": "Falcond",
            "message": f"Profile Active: {profile}",
            "icon": "emblem-system-symbolic"
        })

        try:
            # Create the notification object
            n = Notify.Notification.new(
                config["title"],
                config["message"],
                config["icon"]
            )

            # SET URGENCY TO CRITICAL (2)
            # This forces the notification to appear even in fullscreen games
            n.set_urgency(Notify.Urgency.CRITICAL)

            # Show the notification
            n.show()

            # FORCE CLOSE AFTER 6 SECONDS (6000ms)
            # Increased from 4s to 6s as requested
            GLib.timeout_add(6000, n.close)

        except Exception as e:
            print(f"Failed to show notification: {e}")
            # Fallback: Try simple notify-send if the Python method fails
            try:
                subprocess.run([
                    "notify-send",
                    "--urgency=critical",
                    "--expire-time=6000",
                    f"--icon={config['icon']}",
                    config["title"],
                    config["message"]
                ])
            except:
                pass

    def on_properties_changed(self, interface: str, changed: dict, invalidated: list) -> None:
        """Handle D-Bus property changes."""
        if interface != PPD_INTERFACE:
            return

        if "ActiveProfile" in changed:
            new_profile = str(changed["ActiveProfile"])

            # Skip notification on first detection (startup)
            if self.first_run:
                self.first_run = False
                self.current_profile = new_profile
                print(f"Herald standing by. Current profile: {new_profile}")
                return

            if new_profile != self.current_profile:
                print(f"Announcing: {self.current_profile} -> {new_profile}")
                self.current_profile = new_profile
                self.send_notification(new_profile)

    def get_current_profile(self) -> str:
        """Get the current active power profile."""
        try:
            proxy = self.bus.get_object(PPD_BUS_NAME, PPD_OBJECT_PATH)
            props = dbus.Interface(proxy, DBUS_PROPERTIES_INTERFACE)
            return str(props.Get(PPD_INTERFACE, "ActiveProfile"))
        except dbus.DBusException as e:
            print(f"Error getting current profile: {e}")
            return "unknown"

    def detect_backend(self) -> str:
        """Detect which power profile backend is running."""
        try:
            res = subprocess.run(["systemctl", "is-active", "tuned-ppd"], capture_output=True)
            if res.returncode == 0: return "tuned-ppd"
        except: pass

        try:
            res = subprocess.run(["systemctl", "is-active", "power-profiles-daemon"], capture_output=True)
            if res.returncode == 0: return "power-profiles-daemon"
        except: pass

        return "unknown"

    def check_ppd_available(self) -> bool:
        """Check if power-profiles-daemon is available on D-Bus."""
        try:
            proxy = self.bus.get_object(PPD_BUS_NAME, PPD_OBJECT_PATH)
            props = dbus.Interface(proxy, DBUS_PROPERTIES_INTERFACE)
            props.Get(PPD_INTERFACE, "ActiveProfile")
            return True
        except dbus.DBusException:
            return False

    def setup_signal_handlers(self) -> None:
        """Set up signal handlers for graceful shutdown."""
        def handle_signal(signum, frame):
            print(f"\nReceived signal {signum}, shutting down...")
            if self.loop:
                self.loop.quit()
            try: Notify.uninit()
            except: pass

        signal.signal(signal.SIGINT, handle_signal)
        signal.signal(signal.SIGTERM, handle_signal)

    def run(self) -> int:
        """Main daemon loop."""
        print("Falcond Herald - Active")
        print("=======================")

        DBusGMainLoop(set_as_default=True)

        try:
            self.bus = dbus.SystemBus()
        except dbus.DBusException as e:
            print(f"Error: Cannot connect to system D-Bus: {e}")
            return 1

        if not self.check_ppd_available():
            print("Error: No power profile daemon available on D-Bus.")
            return 1

        self.current_profile = self.get_current_profile()
        print(f"Current profile: {self.current_profile}")

        self.bus.add_signal_receiver(
            self.on_properties_changed,
            signal_name="PropertiesChanged",
            dbus_interface=DBUS_PROPERTIES_INTERFACE,
            bus_name=PPD_BUS_NAME,
            path=PPD_OBJECT_PATH
        )

        self.setup_signal_handlers()

        self.loop = GLib.MainLoop()
        try:
            self.loop.run()
        except KeyboardInterrupt:
            pass

        return 0

def main():
    daemon = FalcondHerald()
    sys.exit(daemon.run())

if __name__ == "__main__":
    main()
HERALD_SCRIPT_EOF

chmod +x "$BIN_DIR/falcond-herald"

# Create the service file
print_status "Installing systemd user service..."
cat > "$SERVICE_DIR/falcond-herald.service" << 'SERVICE_EOF'
[Unit]
Description=Falcond Herald - Power Profile Notification Daemon
Documentation=https://github.com/MurderFromMars/Falcond-Herald
After=graphical-session.target
Wants=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/falcond-herald
Restart=on-failure
RestartSec=5

# Environment for notifications
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
SERVICE_EOF

# Reload systemd
print_status "Reloading systemd user daemon..."
systemctl --user daemon-reload

# Enable and start the service
print_status "Enabling and starting falcond-herald service..."
systemctl --user enable falcond-herald.service
systemctl --user start falcond-herald.service

# Verify it's running
sleep 1
if systemctl --user is-active --quiet falcond-herald.service; then
    print_success "Falcond Herald is now running!"
else
    print_error "Falcond Herald failed to start. Check: systemctl --user status falcond-herald"
    exit 1
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "Useful commands:"
echo "  Status:   systemctl --user status falcond-herald"
echo "  Logs:     journalctl --user -u falcond-herald -f"
echo "  Stop:     systemctl --user stop falcond-herald"
echo "  Restart:  systemctl --user restart falcond-herald"
echo ""
echo "Herald will now announce when Falcond changes power profiles!"
echo ""
