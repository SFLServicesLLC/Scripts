#!/bin/bash

#===============================================================================
# SCRIPT HEADER TEMPLATE
#============================
# Script Name: searchColumnNameDatabase.sh
# Description: MySQL string search script for database and its column names
# 
# Created By: steve.ling@sflservicesllc.com
# Created On: 2024-12-13
# 
# Modified By: 
# Modified On: 
# Modification Notes: 
# 
# Version: 1.0.0
# License: MIT License
# 
# Dependencies: None
# Usage: ./searchColumnNameDatabase.sh <db_name>
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

# Set IFS for newline splitting
IFS=$'\n'

# Function to search within a single database
search_in_db() {
    local DB="$1"
    local USER="$2"
    local PASS="$3"
    local SEARCHSTRING="$4"
    local search_esc=$(echo "$SEARCHSTRING" | sed "s/'/''/g")
    local found_any=false

    echo -e "${YELLOW}Searching in database: $DB${NC}"

    # Get list of tables
    local TABLES=$(mysql -h localhost -u"$USER" -p"$PASS" "$DB" -e "SHOW TABLES;" -B -N 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$TABLES" ]; then
        echo -e "${RED}Error accessing database '$DB' or no tables found.${NC}"
        return 1
    fi

    for table in $TABLES; do
        # Get string-type columns (varchar, char, text variants, enum, set)
        local COLS=$(mysql -h localhost -u"$USER" -p"$PASS" -e "
            SELECT COLUMN_NAME 
            FROM INFORMATION_SCHEMA.COLUMNS 
            WHERE TABLE_SCHEMA = '$DB' 
              AND TABLE_NAME = '$table' 
              AND DATA_TYPE REGEXP '^(varchar|char|text|tinytext|mediumtext|longtext|enum|set)$';
        " -B -N 2>/dev/null)

        if [ -z "$COLS" ]; then
            continue
        fi

        for col in $COLS; do
            # Count matches with substring search (LIKE %search%)
            local COUNT=$(mysql -h localhost -u"$USER" -p"$PASS" "$DB" -e "
                SELECT COUNT(*) 
                FROM \`$table\` 
                WHERE \`$col\` LIKE '%$search_esc%';
            " -B -N 2>/dev/null)

            if [ $? -ne 0 ]; then
                echo -e "${RED}Error querying table '$table', column '$col' in '$DB'.${NC}"
                continue
            fi

            if [ "$COUNT" -gt 0 ]; then
                echo -e "${GREEN}Found $COUNT occurrences of '$SEARCHSTRING' in $DB.$table.$col${NC}"
                found_any=true
            fi
        done
    done

    if [ "$found_any" = false ]; then
        echo -e "${YELLOW}No matches found in database: $DB${NC}"
    fi
    echo ""
}

# Main script
echo -e "${CYAN}MySQL String Search Tool${NC}"

# Prompt for credentials
read -p "Enter MySQL username: " USER
read -s -p "Enter MySQL password: " PASS
echo ""

# List available databases (excluding system ones)
DB_LIST=$(mysql -h localhost -u"$USER" -p"$PASS" -e "SHOW DATABASES;" -B -N 2>/dev/null | grep -Ev '^(information_schema|performance_schema|mysql|sys)$' || echo "")

if [ $? -ne 0 ] || [ -z "$DB_LIST" ]; then
    echo -e "${RED}Error connecting to MySQL or no databases found.${NC}"
    exit 1
fi

echo -e "${CYAN}Available databases:${NC}"
echo "$DB_LIST"

# Prompt for database
read -p "Which database to search (enter name, or 0 for all)? " DB_INPUT
echo ""

# Prompt for search string
read -p "Enter search string: " SEARCHSTRING
if [ -z "$SEARCHSTRING" ]; then
    echo -e "${RED}Search string cannot be empty.${NC}"
    exit 1
fi
echo ""

if [ "$DB_INPUT" = "0" ]; then
    # Search all databases
    if [ -z "$DB_LIST" ]; then
        echo -e "${RED}No databases available.${NC}"
        exit 1
    fi
    for DB in $DB_LIST; do
        search_in_db "$DB" "$USER" "$PASS" "$SEARCHSTRING"
    done
else
    # Search single database
    DB="$DB_INPUT"
    search_in_db "$DB" "$USER" "$PASS" "$SEARCHSTRING"
fi

echo -e "${GREEN}Search completed.${NC}"
exit 0