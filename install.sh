#!/bin/bash
#
# Falcond Herald Improved Installer
# With Wayland/Plasma autostart detection and session-aware launcher
#

set -e

BIN_DIR="$HOME/.local/bin"
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_SCRIPTS_DIR="$HOME/.config/autostart-scripts"

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
echo -e "${CYAN}║                                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# Check for required dependencies
print_status "Checking dependencies..."

MISSING_DEPS=()

if ! command -v python3 &> /dev/null; then
    MISSING_DEPS+=("python3")
fi

if ! python3 -c "import dbus" 2>/dev/null; then
    MISSING_DEPS+=("python3-dbus / python-dbus")
fi

if ! python3 -c "from gi.repository import GLib" 2>/dev/null; then
    MISSING_DEPS+=("python3-gi / python-gobject")
fi

if ! command -v notify-send &> /dev/null; then
    MISSING_DEPS+=("libnotify / libnotify-bin")
fi

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
    echo "  Arch:          sudo pacman -S power-profiles-daemon"
    echo "  Debian/Ubuntu: sudo apt install power-profiles-daemon"
    echo "  Fedora:        sudo dnf install power-profiles-daemon"
    echo ""
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    print_error "Missing dependencies:"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Arch:          sudo pacman -S python-dbus python-gobject libnotify"
    echo "Debian/Ubuntu: sudo apt install python3-dbus python3-gi libnotify-bin"
    echo "Fedora:        sudo dnf install python3-dbus python3-gobject libnotify"
    echo ""
    exit 1
fi

print_success "All dependencies satisfied"

# Detect session type and desktop environment
print_status "Detecting desktop environment..."
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
DESKTOP="${XDG_CURRENT_DESKTOP:-unknown}"

echo "  Session Type: $SESSION_TYPE"
echo "  Desktop: $DESKTOP"

# Remove old systemd service if it exists
if systemctl --user is-enabled falcond-herald.service &>/dev/null; then
    print_warning "Detected old systemd service"
    print_status "Cleaning up old installation..."
    systemctl --user stop falcond-herald.service 2>/dev/null || true
    systemctl --user disable falcond-herald.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/falcond-herald.service"
    systemctl --user daemon-reload
    systemctl --user unset-environment DISPLAY 2>/dev/null || true
    print_success "Old systemd service removed"
fi

mkdir -p "$BIN_DIR"
mkdir -p "$AUTOSTART_DIR"

# Install main script (embedded)
print_status "Installing falcond-herald..."
cat > "$BIN_DIR/falcond-herald" << 'HERALD_EOF'
#!/usr/bin/env python3
import os, sys, signal, subprocess
from pathlib import Path
from datetime import datetime

try:
    import gi
    gi.require_version('Notify', '0.7')
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib, Notify
except ImportError as e:
    print(f"Error: {e}")
    sys.exit(1)

PROFILES = {
    "performance": {"title": "Falcond", "message": "Performance Optimizations Active", "icon": "weather-storm-symbolic"},
    "balanced": {"title": "Falcond", "message": "Standard Performance Restored", "icon": "emblem-default-symbolic"},
    "power-saver": {"title": "Falcond", "message": "Low Power Mode Active.", "icon": "night-light-symbolic"}
}

PPD_BUS = "net.hadess.PowerProfiles"
PPD_PATH = "/net/hadess/PowerProfiles"
PPD_IFACE = "net.hadess.PowerProfiles"
DBUS_PROPS = "org.freedesktop.DBus.Properties"

LOG_DIR = Path.home() / ".local/share/falcond-herald"
LOG_FILE = LOG_DIR / "falcond-herald.log"
PID_FILE = LOG_DIR / "falcond-herald.pid"

class FalcondHerald:
    def __init__(self):
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(PID_FILE, 'w') as f: f.write(str(os.getpid()))
        self.log_file = open(LOG_FILE, 'a')
        self.log("Starting...")
        Notify.init("Falcond")
        self.loop = None
        self.bus = None
        self.current_profile = None
        self.first_run = True

    def log(self, msg):
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"[{ts}] {msg}\n"
        self.log_file.write(line)
        self.log_file.flush()
        print(f"[{ts}] {msg}")

    def send_notification(self, profile):
        cfg = PROFILES.get(profile, {"title": "Falcond", "message": f"{profile}", "icon": "emblem-system-symbolic"})
        try:
            n = Notify.Notification.new(cfg["title"], cfg["message"], cfg["icon"])
            n.set_urgency(Notify.Urgency.CRITICAL)
            n.show()
            GLib.timeout_add(6000, n.close)
            self.log(f"Notification: {cfg['message']}")
        except Exception as e:
            self.log(f"Notification failed: {e}")

    def on_properties_changed(self, iface, changed, inv):
        if iface != PPD_IFACE or "ActiveProfile" not in changed:
            return
        new = str(changed["ActiveProfile"])
        if self.first_run:
            self.first_run = False
            self.current_profile = new
            self.log(f"Current: {new}")
            return
        if new != self.current_profile:
            self.log(f"{self.current_profile} -> {new}")
            self.current_profile = new
            self.send_notification(new)

    def run(self):
        DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SystemBus()
        proxy = self.bus.get_object(PPD_BUS, PPD_PATH)
        props = dbus.Interface(proxy, DBUS_PROPS)
        self.current_profile = str(props.Get(PPD_IFACE, "ActiveProfile"))
        self.log(f"Profile: {self.current_profile}")
        
        self.bus.add_signal_receiver(
            self.on_properties_changed,
            signal_name="PropertiesChanged",
            dbus_interface=DBUS_PROPS,
            bus_name=PPD_BUS,
            path=PPD_PATH
        )
        
        def shutdown(sig, frame):
            self.log("Shutting down...")
            if self.loop: self.loop.quit()
            try: Notify.uninit()
            except: pass
            try: self.log_file.close()
            except: pass
            try: PID_FILE.unlink()
            except: pass
        
        signal.signal(signal.SIGINT, shutdown)
        signal.signal(signal.SIGTERM, shutdown)
        
        self.loop = GLib.MainLoop()
        self.loop.run()

if __name__ == "__main__":
    FalcondHerald().run()
HERALD_EOF

chmod +x "$BIN_DIR/falcond-herald"

# Install session-aware launcher for Wayland/Plasma
print_status "Installing session-aware launcher..."
cat > "$BIN_DIR/falcond-herald-launcher.sh" << 'LAUNCHER_EOF'
#!/bin/bash
# Falcond Herald Session Launcher
# Waits for Wayland/X session to be fully ready before starting

LOG_FILE="$HOME/.local/share/falcond-herald/autostart.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Falcond Herald Autostart Attempt ==="

# Wait for session to be ready
MAX_WAIT=30
WAIT_COUNT=0

log "Waiting for session to be ready..."

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    # Check if we have a display
    if [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; then
        log "Display available: WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=$DISPLAY"
        
        # Check if D-Bus session bus is available
        if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
            log "D-Bus session available: $DBUS_SESSION_BUS_ADDRESS"
            
            # Check if notification daemon is running (important!)
            if pgrep -x "notification-daemon|dunst|mako|swaync|notify-osd" > /dev/null 2>&1 || \
               gdbus introspect --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications > /dev/null 2>&1; then
                log "Notification daemon detected"
                break
            else
                log "No notification daemon yet, waiting..."
            fi
        else
            log "D-Bus session not ready yet..."
        fi
    else
        log "No display yet..."
    fi
    
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    log "ERROR: Timeout waiting for session to be ready"
    exit 1
fi

log "Session ready after $WAIT_COUNT seconds"

# Additional safety delay
sleep 2

# Check if already running
if pgrep -f "python.*falcond-herald" > /dev/null; then
    log "Herald already running, exiting"
    exit 0
fi

# Start the herald
log "Starting falcond-herald..."
exec "$HOME/.local/bin/falcond-herald" >> "$LOG_FILE" 2>&1
LAUNCHER_EOF

chmod +x "$BIN_DIR/falcond-herald-launcher.sh"

# Install management tool (embedded)
print_status "Installing falcond-ctl..."
cat > "$BIN_DIR/falcond-ctl" << 'CTL_EOF'
#!/bin/bash
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BIN="$HOME/.local/bin/falcond-herald"
AUTO="$HOME/.config/autostart/falcond-herald.desktop"
AUTOSCRIPT="$HOME/.config/autostart-scripts/falcond-herald.sh"
LOG_DIR="$HOME/.local/share/falcond-herald"
LOG="$LOG_DIR/falcond-herald.log"
PID="$LOG_DIR/falcond-herald.pid"

msg() { echo -e "${CYAN}[*]${NC} $1"; }
ok() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; }

get_pid() { [ -f "$PID" ] && cat "$PID" || pgrep -f "python.*falcond-herald" || echo ""; }
running() { local p=$(get_pid); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }

start() {
    running && { warn "Already running (PID: $(get_pid))"; return 0; }
    msg "Starting..."
    mkdir -p "$LOG_DIR"
    nohup "$BIN" >> "$LOG" 2>&1 &
    sleep 1
    running && ok "Started (PID: $(get_pid))" || err "Failed"
}

stop() {
    running || { warn "Not running"; return 0; }
    local p=$(get_pid)
    msg "Stopping (PID: $p)..."
    kill "$p" 2>/dev/null || true
    for i in {1..10}; do
        running || { ok "Stopped"; rm -f "$PID"; return 0; }
        sleep 0.5
    done
    kill -9 "$p" 2>/dev/null || true
    rm -f "$PID"
    ok "Stopped"
}

status() {
    echo ""
    echo -e "${CYAN}Falcond Herald Status${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if running; then
        local p=$(get_pid)
        echo -e "State:     ${GREEN}● running${NC}"
        echo -e "PID:       $p"
        echo -e "Memory:    $(ps -p "$p" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')"
        echo -e "Started:   $(ps -p "$p" -o lstart= 2>/dev/null)"
    else
        echo -e "State:     ${RED}○ stopped${NC}"
    fi
    echo ""
    if [ -f "$AUTO" ]; then
        echo -e "Autostart: ${GREEN}enabled${NC} (desktop file)"
    elif [ -f "$AUTOSCRIPT" ]; then
        echo -e "Autostart: ${GREEN}enabled${NC} (script)"
    else
        echo -e "Autostart: ${RED}disabled${NC}"
    fi
    echo "Log file:  $LOG"
    echo ""
}

enable() {
    if [ -f "$AUTO" ] || [ -f "$AUTOSCRIPT" ]; then
        warn "Already enabled"
        return 0
    fi
    msg "Enabling autostart..."
    mkdir -p "$(dirname "$AUTO")"
    cat > "$AUTO" << 'EOF'
[Desktop Entry]
Type=Application
Name=Falcond Herald
Comment=Power Profile Notification Daemon
Exec=%h/.local/bin/falcond-herald-launcher.sh
Icon=preferences-system-power
Terminal=false
Categories=System;
X-KDE-autostart-after=panel
X-GNOME-Autostart-enabled=true
StartupNotify=false
Hidden=false
EOF
    ok "Enabled"
}

disable() {
    [ ! -f "$AUTO" ] && [ ! -f "$AUTOSCRIPT" ] && { warn "Already disabled"; return 0; }
    rm -f "$AUTO" "$AUTOSCRIPT"
    ok "Disabled"
}

logs() {
    [ ! -f "$LOG" ] && { warn "No log file"; return 1; }
    [ "$1" == "-f" ] && tail -f "$LOG" || tail -n 50 "$LOG"
}

help() {
    echo ""
    echo -e "${CYAN}Falcond Herald Management${NC}"
    echo "Usage: falcond-ctl <command>"
    echo ""
    echo "Commands:"
    echo "  start      Start daemon"
    echo "  stop       Stop daemon"
    echo "  restart    Restart daemon"
    echo "  status     Show status"
    echo "  enable     Enable autostart"
    echo "  disable    Disable autostart"
    echo "  logs [-f]  Show logs"
    echo ""
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 1; start ;;
    status) status ;;
    enable) enable ;;
    disable) disable ;;
    logs) logs "$2" ;;
    help|--help|-h) help ;;
    *) err "Unknown: ${1:-}"; help; exit 1 ;;
esac
CTL_EOF

chmod +x "$BIN_DIR/falcond-ctl"

# Smart autostart setup based on desktop environment and session type
print_status "Configuring autostart..."

AUTOSTART_METHOD="desktop-file"

# For KDE Plasma on Wayland, use autostart-scripts
if [[ "$DESKTOP" == *"KDE"* ]] && [[ "$SESSION_TYPE" == "wayland" ]]; then
    print_status "Detected KDE Plasma on Wayland - using autostart-scripts method"
    mkdir -p "$AUTOSTART_SCRIPTS_DIR"
    cat > "$AUTOSTART_SCRIPTS_DIR/falcond-herald.sh" << 'EOF'
#!/bin/bash
~/.local/bin/falcond-herald-launcher.sh &
EOF
    chmod +x "$AUTOSTART_SCRIPTS_DIR/falcond-herald.sh"
    AUTOSTART_METHOD="autostart-script"
    print_success "Created KDE autostart script"
else
    # For other DEs, use standard desktop file with absolute paths
    print_status "Using standard desktop file autostart"
    cat > "$AUTOSTART_DIR/falcond-herald.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Falcond Herald
Comment=Power Profile Notification Daemon
Exec=$BIN_DIR/falcond-herald-launcher.sh
Icon=preferences-system-power
Terminal=false
Categories=System;
X-KDE-autostart-after=panel
X-GNOME-Autostart-enabled=true
StartupNotify=false
Hidden=false
EOF
    chmod +x "$AUTOSTART_DIR/falcond-herald.desktop"
    print_success "Created desktop file autostart entry"
fi

print_status "Starting Falcond Herald..."
"$BIN_DIR/falcond-ctl" start

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "Commands:"
echo "  falcond-ctl start      - Start"
echo "  falcond-ctl stop       - Stop"
echo "  falcond-ctl status     - Status"
echo "  falcond-ctl logs       - View logs"
echo "  falcond-ctl logs -f    - Follow logs"
echo ""
echo "Autostart: ${GREEN}Enabled${NC} (method: $AUTOSTART_METHOD)"
echo ""

if [[ "$AUTOSTART_METHOD" == "desktop-file" ]] && [[ "$DESKTOP" == *"KDE"* ]]; then
    echo -e "${YELLOW}Note for KDE Plasma users:${NC}"
    echo "If autostart doesn't work after reboot, manually add the script via:"
    echo "System Settings → Startup and Shutdown → Autostart → Add Login Script"
    echo "Browse to: $BIN_DIR/falcond-herald-launcher.sh"
    echo ""
fi
