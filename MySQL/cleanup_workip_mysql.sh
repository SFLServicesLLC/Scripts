#!/bin/bash

#===============================================================================
# Script Name: cleanup_workip_mysql.sh
# Description: Clean up WORKIP records (series_number >= 2) for jobs on machine 999
#		that are not present in ULOADC table.
# 
# Created By: Steve Ling
# Created On: 2025-12-04
# 
# Modified By: 
# Modified On: 
# Modification Notes: 
# 
# Version: 1.0.0
# License: MIT License
# 
# Dependencies:]
# Usage:
# 
# WARNING: 
# 
# Changelog:
# - [YYYY-MM-DD]: [VERSION] - [SUMMARY OF CHANGES]
# - [YYYY-MM-DD]: [VERSION] - [INITIAL CREATION]
#===============================================================================

# --------------------- Colors ---------------------
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\033[1;36m'
BOLD='\e[1m'
RESET='\e[0m'

# --------------------- Logging Setup ---------------------
LOG_FILE="cleanup_workip_mysql_$(date +%Y%m%d_%H%M%S).log"

log() {
    local level="$1"
    local message="$2"
    local color=""
    case "$level" in
        INFO)    color="$BLUE" ;;
        SUCCESS) color="$GREEN" ;;
        WARN)    color="$YELLOW" ;;
        ERROR)   color="$RED" ;;
    esac
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}[${timestamp}] [${level}] ${message}${RESET}" | tee -a "$LOG_FILE"
}

# --------------------- MySQL Connection Parameters ---------------------
# Edit these values according to your environment
MYSQL_USER=$(grep "USER=" $DATA/kwsql|cut -d"=" -f2)
MYSQL_PASSWORD=$(grep "PASSWORD=" $DATA/kwsql|cut -d"=" -f2)
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
MYSQL_DATABASE=$(grep "DATA=" $DATA/kwsql|cut -d"=" -f2)

# Build connection options
MYSQL_CONN="-u${MYSQL_USER} -p${MYSQL_PASSWORD} -h${MYSQL_HOST} -P${MYSQL_PORT} ${MYSQL_DATABASE} --silent --skip-column-names"

# Optional: Use a .my.cnf file for credentials instead of plaintext password
# If you prefer that, comment the above and use:
# MYSQL_CONN="${MYSQL_DATABASE} --defaults-extra-file=/path/to/.my.cnf --silent --skip-column-names"

# --------------------- Main ---------------------
log "INFO" "Starting MySQL cleanup script"

log "INFO" "Fetching job_numbers from WORKIP (machine_number=999 AND not in ULOADC)..."

# MySQL query to get job_numbers
JOB_NUMBERS=$(mysql $MYSQL_CONN -e "
SELECT job_number
FROM WORKIP
WHERE machine_number = 999
AND job_number NOT IN (SELECT job_number FROM ULOADC);
")

if [[ $? -ne 0 ]]; then
    log "ERROR" "Failed to execute SELECT query or connect to MySQL"
    exit 1
fi

# Count jobs
JOB_COUNT=$(echo "$JOB_NUMBERS" | grep -v '^$' | wc -l)
log "INFO" "Found ${JOB_COUNT} job_number(s) to process"

if [[ $JOB_COUNT -eq 0 ]]; then
    log "SUCCESS" "No jobs require cleanup � exiting"
    exit 0
fi

# Loop through each job_number
while IFS= read -r job_number; do
    [[ -z "$job_number" ]] && continue

    log "INFO" "Processing job_number: ${BOLD}${job_number}${RESET}"

    # Execute DELETE and capture affected rows
    DELETE_RESULT=$(mysql $MYSQL_CONN -e "
DELETE FROM WORKIP
WHERE job_number = '${job_number}'
  AND machine_number = 999
  AND series_number >= 2;
" 2>&1)

    MYSQL_RC=$?

    if [[ $MYSQL_RC -eq 0 ]]; then
        # MySQL prints "Query OK, N rows affected" on success
        ROWS_DELETED=$(echo "$DELETE_RESULT" | grep -oP 'Query OK, \K\d+(?= rows affected)')
        [[ -z "$ROWS_DELETED" ]] && ROWS_DELETED=0
        log "SUCCESS" "Deleted ${ROWS_DELETED} row(s) for job_number ${job_number}"
    else
        log "ERROR" "DELETE failed for job_number ${job_number}"
        log "ERROR" "MySQL error: ${DELETE_RESULT}"
    fi

done <<< "$JOB_NUMBERS"

log "INFO" "Script completed. Full log saved to ${LOG_FILE}"

exit 0
