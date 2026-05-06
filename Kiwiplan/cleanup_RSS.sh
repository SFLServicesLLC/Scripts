#!/bin/bash

#===============================================================================
# Script Name: cleanup_RSS.sh
# Description: Deletes old data and cleans up orphaned records in dependent tables.
#
# Created By: Steve Ling
# Created On: 2025-12-11
# 
# Modified By: 
# Modified On: 
# Modification Notes: 
# 
# Version: 1.0.0
# License: MIT License
# 
# Dependencies:
#
# Usage for Testing: DRY_RUN=1 CUTOFF_DATE='2024-03-31 23:59:59' ./cleanup_RSS.sh
#
# Usage for Running with Cutoff Date Supplied: CUTOFF_DATE='2024-03-31 23:59:59' ./cleanup_RSS.sh
#
# Usage for Running with hardcoded values: ./cleanup_RSS.sh
# 
# WARNING: This performs irreversible DELETE operations. Use with caution!
# Recommended: Run in dry-run mode first, backup your database, and test on a copy.
# 
# Changelog:
# - [YYYY-MM-DD]: [VERSION] - [SUMMARY OF CHANGES]
# - [YYYY-MM-DD]: [VERSION] - [INITIAL CREATION]
#===============================================================================

# ==================== CONFIGURATION ====================
# MySQL connection details (edit these or override via environment variables)
DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-$(grep "USER=" $DATA/kwsql|cut -d"=" -f2)}"
DB_PASS="${DB_PASS:-$(grep "PASSWORD=" $DATA/kwsql|cut -d"=" -f2)}"
DB_NAME="${DB_NAME:-$(grep "DATA=" $DATA/kwsql|cut -d"=" -f2)}"

# Cutoff date for old records (change if needed)
CUTOFF_DATE="${CUTOFF_DATE:-'2024-03-31 23:59:59'}"

# Log file (timestamped)
LOG_FOLDER="/KIWI/corp/bin"
LOG_FILE="$LOG_FOLDER/cleanup_RSS.log"
LOG_DIR=$(dirname "$LOG_FILE")			# Path of logging directory

# Ensure log directory exists
create_folders() {
if [ ! -d "$LOG_FOLDER" ];then
    log "INFO" "${YELLOW}Creating log folder $LOG_FOLDER${NC}"
    mkdir -p "$LOG_FOLDER"
else
    log "INFO" "${GREEN}Log folder $LOG_FOLDER exists${NC}"
fi
}

# Dry-run mode? (set to 1 for testing - no actual deletes)
DRY_RUN=${DRY_RUN:-0}

# ==================== COLORS ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==================== FUNCTIONS ====================
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

info()    { log "${BLUE}INFO${NC}" "$@"; }
warn()    { log "${YELLOW}WARN${NC}" "$@"; }
error()   { log "${RED}ERROR${NC}" "$@"; }
success() { log "${GREEN}SUCCESS${NC}" "$@"; }

execute_query() {
    local query="$1"
    local desc="$2"

    info "$desc"
    info "Query: $query"

    if [[ $DRY_RUN -eq 1 ]]; then
        warn "DRY RUN: Skipping execution"
        echo "Affected rows: (simulated 0)"
        return 0
    fi

    # Capture affected rows and any errors
    local output
    output=$(mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" \
        -Nse "$query; SELECT ROW_COUNT();" 2>&1)

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Query failed: $output"
        return 1
    fi

    # Last line is ROW_COUNT()
    local affected=$(echo "$output" | tail -n1)
    local rest=$(echo "$output" | sed '$ d')

    if [[ -n "$rest" ]]; then
        info "Query output: $rest"
    fi

    success "Affected rows: $affected"
}

# ==================== MAIN SCRIPT ====================
echo "MySQL Cleanup Script Starting" | tee "$LOG_FILE"
info "Host: $DB_HOST | Database: $DB_NAME | Log: $LOG_FILE"
create_folders
if [[ $DRY_RUN -eq 1 ]]; then
    warn "=== DRY RUN MODE ENABLED - NO CHANGES WILL BE MADE ==="
else
    warn "=== LIVE MODE - DELETES WILL BE EXECUTED ==="
fi

# 1. Delete old records from RSSSTK
execute_query "DELETE FROM RSSSTK WHERE received_js <= '$CUTOFF_DATE'" \
    "Deleting old rows from RSSSTK (before $CUTOFF_DATE)"

# 2. Delete old records from RSSHST
execute_query "DELETE FROM RSSHST WHERE received_js <= '$CUTOFF_DATE'" \
    "Deleting old rows from RSSHST (before $CUTOFF_DATE)"

# 3. Clean orphaned ORGSUP
execute_query "DELETE FROM ORGSUP WHERE roll_id NOT IN (SELECT unique_roll_id FROM RSSSTK)" \
    "Deleting orphaned rows in ORGSUP"

# 4. Clean orphaned INVLOC
execute_query "DELETE FROM INVLOC WHERE unique_inv_id NOT IN (SELECT unique_roll_id FROM RSSSTK)" \
    "Deleting orphaned rows in INVLOC"

# 5. Clean orphaned INVHST
execute_query "DELETE FROM INVHST WHERE unique_inv_id NOT IN (SELECT unique_roll_id FROM RSSHST)" \
    "Deleting orphaned rows in INVHST"

# 6. Clean orphaned HSTVAL
execute_query "DELETE FROM HSTVAL WHERE roll_id NOT IN (SELECT unique_roll_id FROM RSSHST)" \
    "Deleting orphaned rows in HSTVAL"

success "Cleanup script completed."
echo "Log saved to: $LOG_FILE"

exit 0
