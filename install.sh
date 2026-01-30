#!/bin/bash
#
# Falcond Herald Installer
# Installs the power profile notification daemon
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Install the daemon script
print_status "Installing falcond-herald to $BIN_DIR..."
cp "$SCRIPT_DIR/falcond-herald" "$BIN_DIR/falcond-herald"
chmod +x "$BIN_DIR/falcond-herald"

# Install the service file
print_status "Installing systemd user service..."
cp "$SCRIPT_DIR/falcond-herald.service" "$SERVICE_DIR/falcond-herald.service"

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
