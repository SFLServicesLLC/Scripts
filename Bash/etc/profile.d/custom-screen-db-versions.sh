#!/bin/bash

#===============================================================================
# SCRIPT HEADER TEMPLATE
#============================
# Script Name: custom-screen-db-versions.sh
# Description: Auto-Display Database Versions on Login (with colors!)
#               PostgreSQL, MySQL/MariaDB, SQLite, MongoDB, Redis
# 
# Created By: robinhood1995@yahoo.com & Grok.com
# Created On: 2025-12-18
# 
# Modified By: 
# Modified On: 
# Modification Notes:
# 
# Version: 1.0.0
# License: MIT License
# 
# Dependencies: Whiptail
# Usage: Auto Displays when you create file in this folder /etc/profile.d/custom-screen-db-versions.sh
# Run:   sudo chmod +x /etc/profile.d/custom-screen-db-versions.sh
# 
# WARNING:
# 
# Changelog:
# - [YYYY-MM-DD]: [VERSION] - [SUMMARY OF CHANGES]
# - [YYYY-MM-DD]: [VERSION] - [INITIAL CREATION]
#===============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Skip in non-interactive shells
[[ -z "$PS1" || ! -t 0 ]] && exit 0

# Show only once per session
SESSION_MARKER="/tmp/db_versions_shown_$$"
if [[ -f "$SESSION_MARKER" ]]; then
    AUTO_DISPLAY=0
else
    AUTO_DISPLAY=1
    touch "$SESSION_MARKER"
    trap 'rm -f "$SESSION_MARKER" 2>/dev/null' EXIT
fi

clear

echo -e "${CYAN}${BOLD}==================================================${NC}"
echo -e "${CYAN}${BOLD}   Database Versions & Ports on $(hostname -s)${NC}"
echo -e "${CYAN}${BOLD}   $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${CYAN}${BOLD}==================================================${NC}"

# Helper: Build associative array of PostgreSQL major version -> listening port
get_postgres_port_map() {
    declare -A port_map
    mapfile -t lines < <(ss -ltnp 2>/dev/null | grep '"postgres"')
    for line in "${lines[@]}"; do
        port=$(echo "$line" | awk '{print $4}' | cut -d: -f2)
        pid=$(echo "$line" | grep -o 'pid=[0-9]*' | cut -d= -f2)
        if [[ -n "$pid" && -n "$port" ]]; then
            # Extract version from process name (e.g., "postgres: 15/main" → 15)
            ver=$(ps -p "$pid" -o args= 2>/dev/null | grep -o 'postgres: [0-9][0-9]*' | grep -o '[0-9][0-9]*' | head -1)
            if [[ -n "$ver" ]]; then
                port_map["$ver"]="$port"
            fi
        fi
    done
    for ver in "${!port_map[@]}"; do
        echo "port_map[$ver]=${port_map[$ver]}"
    done
}

# PostgreSQL versions with per-version port
get_postgres_versions() {
    local versions=()
    local found=0

    declare -A port_map
    eval "$(get_postgres_port_map)"

    # RHEL AppStream modules
    mapfile -t pg_packages < <(rpm -qa 'postgresql*-server' --queryformat '%{NAME}-%{VERSION}\n' 2>/dev/null | grep -v '\-devel\|-libs\|-contrib\|-docs\|-plink' | sort -u)
    for pkg in "${pg_packages[@]}"; do
        if [[ -n "$pkg" ]]; then
            ver=$(echo "$pkg" | sed -E 's/.*-([0-9][0-9]*)$/\1/')
            versions+=("$ver|PostgreSQL $ver (RHEL AppStream)")
            found=1
        fi
    done

    # PGDG repository
    mapfile -t pgdg_packages < <(rpm -qa 'postgresql[0-9][0-9]-server' 'postgresql[0-9][0-9][0-9]-server' 2>/dev/null | sort -u)
    for pkg in "${pgdg_packages[@]}"; do
        if [[ "$pkg" =~ postgresql([0-9]{2,3})-server ]]; then
            ver="${BASH_REMATCH[1]}"
            full_ver=$(rpm -q --queryformat '%{VERSION}' "$pkg" 2>/dev/null)
            versions+=("$ver|PostgreSQL $ver ($full_ver via PGDG repo)")
            found=1
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}PostgreSQL: None detected${NC}"
        return
    fi

    echo -e "${GREEN}${BOLD}PostgreSQL:${NC}"
    for entry in "${versions[@]}"; do
        IFS='|' read -r major desc <<< "$entry"
        if [[ -n "${port_map[$major]}" ]]; then
            echo -e "    ${GREEN}• $desc  → listening on port ${port_map[$major]}${NC}"
        else
            echo -e "    ${GREEN}• $desc  (not listening on TCP)${NC}"
        fi
    done
}

# MySQL / MariaDB
get_mysql_versions() {
    if command -v mariadb >/dev/null 2>&1; then
        ver=$(mariadb --version 2>/dev/null | grep -oP 'Distrib \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        if ss -ltn 2>/dev/null | grep -q ':3306 '; then
            echo -e "${GREEN}MariaDB: $ver  → listening on port 3306${NC}"
        else
            echo -e "${GREEN}MariaDB: $ver  (not listening on 3306)${NC}"
        fi
    elif command -v mysql >/dev/null 2>&1; then
        ver=$(mysql --version 2>/dev/null | grep -oP 'Distrib \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        if ss -ltn 2>/dev/null | grep -q ':3306 '; then
            echo -e "${GREEN}MySQL: $ver  → listening on port 3306${NC}"
        else
            echo -e "${GREEN}MySQL: $ver  (not listening on 3306)${NC}"
        fi
    elif rpm -q mysql-community-server >/dev/null 2>&1; then
        ver=$(rpm -q --queryformat '%{VERSION}' mysql-community-server 2>/dev/null)
        echo -e "${GREEN}MySQL: $ver (community, package only)${NC}"
    elif rpm -q mysql-server >/dev/null 2>&1; then
        ver=$(rpm -q --queryformat '%{VERSION}' mysql-server 2>/dev/null)
        echo -e "${GREEN}MySQL: $ver (package only)${NC}"
    else
        echo -e "${YELLOW}MySQL/MariaDB: None detected${NC}"
    fi
}

# SQLite
get_sqlite_version() {
    if command -v sqlite3 >/dev/null 2>&1; then
        ver=$(sqlite3 --version 2>/dev/null | awk '{print $1}')
        echo -e "${GREEN}SQLite: $ver  (file-based, no server port)${NC}"
    elif rpm -q sqlite >/dev/null 2>&1; then
        ver=$(rpm -q --queryformat '%{VERSION}' sqlite 2>/dev/null)
        echo -e "${GREEN}SQLite: $ver (package only)${NC}"
    else
        echo -e "${YELLOW}SQLite: None detected${NC}"
    fi
}

# MongoDB
get_mongodb_version() {
    if command -v mongod >/dev/null 2>&1; then
        ver=$(mongod --version 2>/dev/null | head -1 | grep -oP 'db version v\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        if ss -ltn 2>/dev/null | grep -q ':27017 '; then
            echo -e "${GREEN}MongoDB: $ver  → listening on port 27017${NC}"
        else
            echo -e "${GREEN}MongoDB: $ver  (not listening on 27017)${NC}"
        fi
    elif rpm -q mongodb-org-server >/dev/null 2>&1; then
        ver=$(rpm -q --queryformat '%{VERSION}' mongodb-org-server 2>/dev/null)
        echo -e "${GREEN}MongoDB: $ver (package only)${NC}"
    else
        echo -e "${YELLOW}MongoDB: None detected${NC}"
    fi
}

# Redis
get_redis_version() {
    if command -v redis-server >/dev/null 2>&1; then
        ver=$(redis-server --version 2>/dev/null | grep -oP 'Redis server v=\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        if ss -ltn 2>/dev/null | grep -q ':6379 '; then
            echo -e "${GREEN}Redis: $ver  → listening on port 6379${NC}"
        else
            echo -e "${GREEN}Redis: $ver  (not listening on 6379)${NC}"
        fi
    elif rpm -q redis >/dev/null 2>&1; then
        ver=$(rpm -q --queryformat '%{VERSION}' redis 2>/dev/null)
        echo -e "${GREEN}Redis: $ver (package only)${NC}"
    else
        echo -e "${YELLOW}Redis: None detected${NC}"
    fi
}

# === Auto Display ===
if [[ $AUTO_DISPLAY -eq 1 ]]; then
    get_postgres_versions
    echo
    get_mysql_versions
    echo
    get_sqlite_version
    echo
    get_mongodb_version
    echo
    get_redis_version
    echo
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${MAGENTA}Tip: Run 'dbversions' to view this again interactively.${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo
fi

# === Interactive function ===
dbversions() {
    if ! command -v whiptail >/dev/null 2>&1; then
        echo "whiptail not available. Showing colored output:"
        echo
        get_postgres_versions
        echo
        get_mysql_versions
        echo
        get_sqlite_version
        echo
        get_mongodb_version
        echo
        get_redis_version
        return
    fi

    while true; do
        choice=$(whiptail --title "Database Versions & Ports - $(hostname)" --menu "Choose an option:" 20 78 5 \
            "1" "Show all versions & ports" \
            "2" "Refresh and show all" \
            "3" "Exit" 3>&1 1>&2 2>&3)

        case "$choice" in
            1|2)
                clear
                echo -e "${CYAN}${BOLD}=== Database Versions & Ports on $(hostname) ===${NC}"
                echo
                get_postgres_versions
                echo
                get_mysql_versions
                echo
                get_sqlite_version
                echo
                get_mongodb_version
                echo
                get_redis_version
                echo
                read -p "Press Enter to continue..."
                ;;
            *) return ;;
        esac
    done
}

export -f dbversions