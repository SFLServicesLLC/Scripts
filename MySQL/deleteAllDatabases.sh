#!/bin/bash

#===============================================================================
# SCRIPT HEADER TEMPLATE
#============================
# Script Name: deleteAllDatabases.sh
# Description: This is to delete a set of MySQL databases with a prefix
# 
# Created By: steve.ling@sflservicesllc.com
# Created On: 2024-10-13
# 
# Modified By: 
# Modified On: 
# Modification Notes: 
# 
# Version: 1.0.0
# License: MIT License
# 
# Dependencies: None
# Usage: ./deleteAllDatabases.sh <prefix>
# 
# WARNING: Becareful to run on production MySQL
# 
# Changelog:
# - [YYYY-MM-DD]: [VERSION] - [SUMMARY OF CHANGES]
# - [YYYY-MM-DD]: [VERSION] - [INITIAL CREATION]
#===============================================================================

# Global Variables
# ----------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Colors for output (optional)
# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to print header info (optional utility)
print_header() {
    echo -e "${GREEN}Running ${SCRIPT_NAME}${NC}"
    echo -e "${YELLOW}Description: ${DESCRIPTION}${NC}"
    echo -e "${YELLOW}Version: ${VERSION}${NC}"
}

# Main script logic starts here
# -----------------------------
DESCRIPTION="This is to delete a set of MySQL databases with a prefix"
VERSION="1.0.0"

# Example: print_header  # Uncomment to use

if [ $# != "1" ];then
    echo "Not enough arguments.";
    echo "Usage: $0 <db_prefix>";
    exit;
fi;

DB=${1}
echo `mysql -e" show databases like '${DB}_%';" | egrep -v "Database" | while read x ; do echo "DROP DATABASE $x;" ; done`

exit 0