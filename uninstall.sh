#!/bin/bash
#
# Falcond Herald Uninstaller
#

set -e

BIN_DIR="$HOME/.local/bin"
SERVICE_DIR="$HOME/.config/systemd/user"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${CYAN}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }

echo ""
echo -e "${RED}Uninstalling Falcond Herald...${NC}"
echo ""

# Stop and disable service
if systemctl --user is-active --quiet falcond-herald.service 2>/dev/null; then
    print_status "Stopping falcond-herald service..."
    systemctl --user stop falcond-herald.service
fi

if systemctl --user is-enabled --quiet falcond-herald.service 2>/dev/null; then
    print_status "Disabling falcond-herald service..."
    systemctl --user disable falcond-herald.service
fi

# Remove files
print_status "Removing files..."
rm -f "$BIN_DIR/falcond-herald"
rm -f "$SERVICE_DIR/falcond-herald.service"

# Reload systemd
print_status "Reloading systemd..."
systemctl --user daemon-reload

print_success "Falcond Herald has been uninstalled"
echo ""
