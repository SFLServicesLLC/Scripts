#!/bin/bash
#==============================================================================
#TITLE:		mysql_backup.sh
#DESCRIPTION:	script for automating the mysql backups on development computer
#AUTHOR:	Steve Ling
#DATE:		2024-08-24
#VERSION:	1.0
#USAGE:		./mysql_backup.sh
#CRON:
  # example cron for daily db backup @ 9:15 am
  # min  hr mday month wday command
  # 15   9  *    *     *    /opt/scripts/mysql_backup.sh

#RESTORE FROM BACKUP
  #$ gunzip < [backupfile.sql.gz] | mysql -u [uname] -p[pass] [dbname]

#==============================================================================
# CUSTOM SETTINGS
#==============================================================================

set -uo pipefail

# Define colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'
FLASH='\033[5m'

# directory to put the backup files
MAINDIR=/mnt/backups
HNAME=$(hostname -s)

# Number of days to keep backups
KEEP_BACKUPS_FOR=7 #days

# Minimum free space (in MB) required on $MAINDIR before backups will run
MIN_FREE_MB=1024

# Credentials read by mysql/mysqldump for connection defaults. Both files
# below are picked up automatically by the client library (no flags needed):
#   ~/.my.cnf       - plaintext option file
#   ~/.mylogin.cnf  - encrypted login-path file (set via mysql_config_editor)
# To use this use the script called setup_mysql_login.sh to set up the credentials for the backup script to use.
MYSQL_CNF="${MYSQL_CNF:-$HOME/.my.cnf}"
MYSQL_LOGIN_CNF="${MYSQL_LOGIN_CNF:-$HOME/.mylogin.cnf}"

LOG_TAG="mysql_backup"

# Persistent log file (falls back to $MAINDIR if /var/log isn't writable)
LOGFILE="/var/log/${LOG_TAG}.log"
if ! touch "$LOGFILE" 2>/dev/null; then
    LOGFILE="$MAINDIR/${LOG_TAG}.log"
    touch "$LOGFILE" 2>/dev/null || LOGFILE="/dev/null"
fi

# log MESSAGE [LEVEL]
# Sends MESSAGE to syslog and $LOGFILE always; when run from an interactive
# terminal (not cron), also prints it to stdout colorized by LEVEL.
log() {
    local msg="$1" level="${2:-INFO}" color

    case "$level" in
        SUCCESS)  color="$GREEN" ;;
        WARN)     color="$YELLOW" ;;
        ERROR)    color="$RED" ;;
        CRITICAL) color="${FLASH}${BOLD}${RED}" ;;
        *)        color="$CYAN" ;;
    esac

    logger -t "$LOG_TAG" -- "$msg"
    printf '%s [%s] %s\n' "$(date '+%F %T')" "$level" "$msg" >> "$LOGFILE" 2>/dev/null

    if [ -t 1 ]; then
        printf '%b%s%b\n' "$color" "$msg" "$NC"
    fi
}

#==============================================================================
# METHODS
#==============================================================================

# Locate the mysql/mariadb client (some hosts only ship "mariadb")
if command -v mysql >/dev/null 2>&1; then
    PROG="mysql"
elif command -v mariadb >/dev/null 2>&1; then
    PROG="mariadb"
else
    log "Failure: neither 'mysql' nor 'mariadb' command was found in the PATH." CRITICAL
    exit 1
fi
log "Using '$PROG' client." INFO

# Locate the dump binary (some hosts only ship "mariadb-dump", not "mysqldump")
if command -v mysqldump >/dev/null 2>&1; then
    DUMP_PROG="mysqldump"
elif command -v mariadb-dump >/dev/null 2>&1; then
    DUMP_PROG="mariadb-dump"
else
    log "Failure: neither 'mysqldump' nor 'mariadb-dump' command was found in the PATH." CRITICAL
    exit 1
fi
log "Using '$DUMP_PROG' for dumps." INFO

# Warn if a credentials file is present but readable by group/other
if [ -f "$MYSQL_CNF" ]; then
    CNF_PERMS=$(stat -c '%a' "$MYSQL_CNF" 2>/dev/null)
    if [ -n "$CNF_PERMS" ] && [ "${CNF_PERMS: -2}" != "00" ]; then
        log "Warning: $MYSQL_CNF is readable/writable by group or other (mode $CNF_PERMS). Run: chmod 600 $MYSQL_CNF" WARN
    fi
fi

if [ -f "$MYSQL_LOGIN_CNF" ]; then
    LOGIN_CNF_PERMS=$(stat -c '%a' "$MYSQL_LOGIN_CNF" 2>/dev/null)
    if [ -n "$LOGIN_CNF_PERMS" ] && [ "${LOGIN_CNF_PERMS: -2}" != "00" ]; then
        log "Warning: $MYSQL_LOGIN_CNF is readable/writable by group or other (mode $LOGIN_CNF_PERMS). Run: chmod 600 $MYSQL_LOGIN_CNF" WARN
    fi
fi

if [ ! -f "$MYSQL_CNF" ] && [ ! -f "$MYSQL_LOGIN_CNF" ]; then
    log "Notice: neither $MYSQL_CNF nor $MYSQL_LOGIN_CNF found; relying on default (e.g. socket) authentication." INFO
fi

# Prevent overlapping runs if a previous backup is still in progress
LOCKFILE="/var/run/${LOG_TAG}.lock"
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    log "Another instance of $LOG_TAG is already running. Exiting." CRITICAL
    exit 1
fi

log "Checking if $MAINDIR/$HNAME directory exists" INFO
if [ ! -d "$MAINDIR/$HNAME" ]; then
    log "$MAINDIR/$HNAME does not exist. Creating it." INFO
    if ! mkdir -p "$MAINDIR/$HNAME"; then
        log "Failure: could not create $MAINDIR/$HNAME" CRITICAL
        exit 1
    fi
fi

# Abort if there isn't enough free space to safely write backups
AVAIL_MB=$(df --output=avail -m "$MAINDIR" 2>/dev/null | tail -n1 | tr -d ' ')
if [ -z "$AVAIL_MB" ]; then
    log "Warning: could not determine free space on $MAINDIR; continuing anyway." WARN
elif [ "$AVAIL_MB" -lt "$MIN_FREE_MB" ]; then
    log "Failure: only ${AVAIL_MB}MB free on $MAINDIR, need at least ${MIN_FREE_MB}MB. Aborting." CRITICAL
    exit 1
fi

#Backing up the databases
#Excludes system databases
FAILED=0
DUMP_ERR=$(mktemp)
while IFS= read -r DATABASE; do
    FILE="$(date +%Y.%m.%d_%H).${HNAME}.${DATABASE}.sql.gz"
    log "Backing up $DATABASE to $FILE" INFO
    if "$DUMP_PROG" --complete-insert --routines --triggers --single-transaction \
        --databases "$DATABASE" 2>"$DUMP_ERR" \
        | gzip > "$MAINDIR/$HNAME/$FILE"; then
        log "Backed up $DATABASE successfully" SUCCESS
    else
        log "Failure: backup of $DATABASE failed" ERROR
        if [ -s "$DUMP_ERR" ]; then
            while IFS= read -r errline; do log "  $errline" ERROR; done < "$DUMP_ERR"
        fi
        FAILED=1
    fi
done < <("$PROG" -e "show databases" | grep -v -e '^Database$' -e '^performance_schema$' -e '^information_schema$' -e '^sys$' -e '^test$')
rm -f "$DUMP_ERR"

DELETED=$(find "$MAINDIR/$HNAME/" -name '20??.??.??_??.*.sql.gz' -mtime +$KEEP_BACKUPS_FOR -exec rm -v {} \;)
if [ -n "$DELETED" ]; then
    while IFS= read -r line; do
        log "$line" INFO
    done <<< "$DELETED"
fi

if [ "$FAILED" -ne 0 ]; then
    log "One or more database backups failed." ERROR
    exit 1
fi

log "All backups completed successfully." SUCCESS
exit 0
#==============================================================================
