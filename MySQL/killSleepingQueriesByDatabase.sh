#!/bin/bash

#===============================================================================
# Script Name: killSleepingQueriesByDatabase.sh
# Description: This is to kill all sleeping queries by database name
# 
# Created By: steve.ling@sflservicesllc.com
# Created On: 2024-10-12
# 
# Modified By: 
# Modified On: 
# Modification Notes: 
# 
# Version: 1.0.0
# License: MIT License
# 
# Dependencies: None
# Usage: ./killSleepingQueriesByDatabase.sh <db_name>
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
DESCRIPTION="This is to kill all sleeping queries by database name"
VERSION="1.0.0"

# Example: print_header  # Uncomment to use

if [ $# != "1" ]; then
    echo -e "${RED}Not enough arguments.${NC}";
    echo -e "${YELLOW}Usage: $0 <db_name>${NC}";
    exit 1;
fi;

DB=${1};

echo -e "${CYAN}Enter MySQL username: ${NC}";
read USERNAME;
echo -e "${CYAN}Enter MySQL password: ${NC}";
read -s PASSWORD;
echo "";

QUERY_IDS=$(mysql -u ${USERNAME} -h localhost ${DB} -p${PASSWORD} -e "SELECT * FROM INFORMATION_SCHEMA.PROCESSLIST WHERE COMMAND ='Sleep' and HOST='localhost';" | sed 's/\(^[0-9]*\).*/\1/' | tail -n +2);

if [ -z "$QUERY_IDS" ]; then
    echo -e "${GREEN}No sleeping queries found.${NC}";
    exit 0;
fi;

for i in $QUERY_IDS; do
    echo -e "${YELLOW}Killing query ${i}...${NC}";
    mysql -u ${USERNAME} -h localhost ${DB} -p${PASSWORD} -e "kill query ${i}" > /dev/null 2>&1;
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Query ${i} killed successfully.${NC}";
    else
        echo -e "${RED}Failed to kill query ${i}.${NC}";
    fi;
done;

exit 0