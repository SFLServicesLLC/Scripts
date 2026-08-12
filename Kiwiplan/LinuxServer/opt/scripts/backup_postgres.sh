#!/bin/bash
#==============================================================================
# TITLE: postgres_backup.sh
# DESCRIPTION: Backup multiple PostgreSQL instances (different ports)
# VERSION: 1.3 - explicit version mapping (PG 16 + 17)
# USAGE: ./postgres_backup.sh
#        (or via cron)
#==============================================================================

set -euo pipefail

# Define colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'
FLASH='\033[5m'

#==============================================================================
# CUSTOM SETTINGS
#==============================================================================
MAINDIR=/mnt/backups
HNAME=$(hostname -s)
KEEP_BACKUPS_FOR=7   # days

# Minimum free space (in MB) required on $MAINDIR before backups will run
MIN_FREE_MB=1024

# Credentials file read by psql/pg_dump for password-based auth
# Use this script to set up the credentials for the backup script to use: setup_postgres_pgpass.sh
PGPASS_FILE="${PGPASSFILE:-$HOME/.pgpass}"

LOG_TAG="postgres-backup"

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

# ------------------------------------------------
# Define your PostgreSQL instances here
# Format: "port:username:description:bin_dir"
# ------------------------------------------------
declare -A PG_INSTANCES
PG_INSTANCES=(
    ["default"]="5432:postgres:default instance:/usr/pgsql-16/bin"
    ["instance2"]="5433:postgres:second instance (port 5433):/usr/pgsql-17/bin"
)

#==============================================================================
# PRE-FLIGHT CHECKS
#==============================================================================

# Warn if a .pgpass credentials file is present but not properly locked down
# (PostgreSQL silently ignores .pgpass unless group/other access is denied)
if [ -f "$PGPASS_FILE" ]; then
    PGPASS_PERMS=$(stat -c '%a' "$PGPASS_FILE" 2>/dev/null)
    if [ -n "$PGPASS_PERMS" ] && [ "${PGPASS_PERMS: -2}" != "00" ]; then
        log "Warning: $PGPASS_FILE is readable/writable by group or other (mode $PGPASS_PERMS). PostgreSQL will ignore it until you run: chmod 600 $PGPASS_FILE" WARN
    fi
else
    log "Notice: $PGPASS_FILE not found; relying on peer/trust authentication." INFO
fi

# Prevent overlapping runs if a previous backup is still in progress
LOCKFILE="/var/run/${LOG_TAG}.lock"
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    log "Another instance of $LOG_TAG is already running. Exiting." CRITICAL
    exit 1
fi

# Abort if there isn't enough free space to safely write backups
AVAIL_MB=$(df --output=avail -m "$MAINDIR" 2>/dev/null | tail -n1 | tr -d ' ')
if [ -z "$AVAIL_MB" ]; then
    log "Warning: could not determine free space on $MAINDIR; continuing anyway." WARN
elif [ "$AVAIL_MB" -lt "$MIN_FREE_MB" ]; then
    log "Failure: only ${AVAIL_MB}MB free on $MAINDIR, need at least ${MIN_FREE_MB}MB. Aborting." CRITICAL
    exit 1
fi

#==============================================================================
# BACKUP FUNCTION
#==============================================================================
backup_instance() {
    local port="$1"
    local user="$2"
    local desc="$3"
    local bin_dir="$4"

    local PG_DUMP="$bin_dir/pg_dump"
    local PSQL="$bin_dir/psql"
    local subdir="${desc// /_}"
    local backup_dir="$MAINDIR/$HNAME/$subdir"
    local INSTANCE_FAILED=0

    log "Starting backup for instance: $desc (port $port)" INFO
    log "  Using binaries from: $bin_dir" INFO

    # Sanity check
    if [[ ! -x "$PG_DUMP" || ! -x "$PSQL" ]]; then
        log "ERROR: pg_dump or psql not found/executable in $bin_dir" ERROR
        return 1
    fi

    mkdir -p "$backup_dir" || {
        log "ERROR: Cannot create $backup_dir" ERROR
        return 1
    }

    # Get list of user databases (Unix socket)
    local PSQL_ERR
    PSQL_ERR=$(mktemp)
    local databases
    databases=$(
        "$PSQL" -h localhost -p "$port" -U "$user" -t -A -c "
            SELECT datname FROM pg_database
            WHERE datistemplate = false
              AND datname NOT IN ('postgres', 'template0', 'template1')
            ORDER BY datname;
        " 2>"$PSQL_ERR"
    ) || {
        log "ERROR: Failed to query database list on port $port ($desc)" ERROR
        if [ -s "$PSQL_ERR" ]; then
            while IFS= read -r errline; do log "    $errline" ERROR; done < "$PSQL_ERR"
        fi
        rm -f "$PSQL_ERR"
        return 1
    }
    rm -f "$PSQL_ERR"

    if [[ -z "$databases" ]]; then
        log "WARNING: No user databases found on port $port ($desc)" WARN
        return 0
    fi

    local DUMP_ERR
    DUMP_ERR=$(mktemp)

    for db in $databases; do
        local timestamp
        timestamp=$(date +%Y.%m.%d_%H)
        local filename="${timestamp}.${HNAME}.${subdir}.${db}.sql.gz"
        local outfile="$backup_dir/$filename"

        log "  -> Dumping $db -> $filename" INFO

        if "$PG_DUMP" \
            -h localhost \
            -p "$port" \
            -U "$user" \
            --clean \
            --if-exists \
            --no-owner \
            --no-privileges \
            "$db" 2>"$DUMP_ERR" | gzip > "$outfile"; then
            log "  Success: $db" SUCCESS
        else
            log "  ERROR: Backup failed for $db (port $port)" ERROR
            if [ -s "$DUMP_ERR" ]; then
                while IFS= read -r errline; do log "    $errline" ERROR; done < "$DUMP_ERR"
            fi
            rm -f "$outfile"
            INSTANCE_FAILED=1
        fi
    done
    rm -f "$DUMP_ERR"

    # Cleanup old backups
    log "  Cleaning up files older than ${KEEP_BACKUPS_FOR} days" INFO
    local DELETED
    DELETED=$(find "$backup_dir" \
        -type f \
        -name '20??.??.??_??.*.sql.gz' \
        -mtime +$KEEP_BACKUPS_FOR \
        -print -delete 2>/dev/null)
    if [ -n "$DELETED" ]; then
        while IFS= read -r f; do
            log "  Deleted: $f" INFO
        done <<< "$DELETED"
    fi

    return "$INSTANCE_FAILED"
}

#==============================================================================
# MAIN
#==============================================================================
log "Starting multi-instance PostgreSQL backup - $(date '+%Y-%m-%d %H:%M:%S')" INFO

FAILED=0
for key in "${!PG_INSTANCES[@]}"; do
    IFS=':' read -r port user desc bin_dir <<< "${PG_INSTANCES[$key]}"
    backup_instance "$port" "$user" "$desc" "$bin_dir" || FAILED=1
done

if [ "$FAILED" -ne 0 ]; then
    log "One or more instance backups had failures." ERROR
    exit 1
fi

log "Multi-instance backup job finished - $(date '+%Y-%m-%d %H:%M:%S')" SUCCESS
exit 0
