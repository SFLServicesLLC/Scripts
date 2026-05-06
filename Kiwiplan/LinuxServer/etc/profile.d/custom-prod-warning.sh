#===============================================================================
# SCRIPT HEADER TEMPLATE
#============================
# Script Name: custom-prod-warning.sh
# Description: Display warning to use for production servers
# 
# Created By: robinhood1995@yahoo.com
# Created On: 2025-12-18
# 
# Modified By: 
# Modified On: 
# Modification Notes:
# 
# Version: 1.0.0
# License: MIT License
# 
# Dependencies: 
# Usage: Auto Displays when you create file in this folder /etc/profile.d/custom-prod-warning.sh
#
# WARNING:
# 
# Changelog:
# - [YYYY-MM-DD]: [VERSION] - [SUMMARY OF CHANGES]
# - [YYYY-MM-DD]: [VERSION] - [INITIAL CREATION]
#===============================================================================

# Colorful PRODUCTION warning banner for interactive logins

if [[ -n "$PS1" && -t 0 ]]; then  # Only for interactive terminals (e.g., SSH/console login)
    RED='\033[1;31m'      # Bold red
    YELLOW='\033[1;33m'   # Bold yellow
    NC='\033[0m'          # No color reset

    echo
    if command -v figlet >/dev/null; then
        figlet -f big "PRODUCTION" | while IFS= read -r line; do echo -e "${RED}$line${NC}"; done
        figlet -f big "SERVER!!"  | while IFS= read -r line; do echo -e "${RED}$line${NC}"; done
    else
        echo -e "${RED}***** PRODUCTION SERVER ***** ${NC}"
    fi
    echo
    echo -e "${YELLOW}                *** EXTREME CAUTION REQUIRED *** ${NC}"
    echo -e "${RED}This is a LIVE PRODUCTION system. ${NC}"
    echo -e "${RED}Unauthorized access is strictly prohibited. ${NC}"
    echo -e "${RED}All activity is logged and monitored. ${NC}"
    echo -e "${YELLOW}Think twice before running commands! ${NC}"
    echo
fi