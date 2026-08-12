#!/bin/bash
#==============================================================================
#TITLE:        setup_postgres_pgpass.sh
#DESCRIPTION:  Sets up ~/.pgpass for postgres_backup_multi.sh, one line per
#              instance defined in PG_INSTANCES below (keep this table in
#              sync with the same table in postgres_backup_multi.sh).
#
#              Also handles the case where a DB role has no password set
#              yet (common right after install: local peer/trust auth only)
#              by offering to set one via the "postgres" OS account's local
#              peer-authenticated socket connection.
#
#AUTHOR:       Steve Ling
#USAGE:        sudo ./setup_postgres_pgpass.sh
#==============================================================================

set -uo pipefail

# ------------------------------------------------
# Must match postgres_backup_multi.sh's PG_INSTANCES
# Format: "port:username:description:bin_dir"
# ------------------------------------------------
declare -A PG_INSTANCES
PG_INSTANCES=(
    ["default"]="5432:postgres:default instance:/usr/pgsql-16/bin"
    ["instance2"]="5433:postgres:second instance (port 5433):/usr/pgsql-17/bin"
)

PGHOST_FIELD="localhost"   # must match the -h value used in postgres_backup_multi.sh

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

info() { printf '%b%s%b\n' "$CYAN" "$1" "$NC"; }
ok()   { printf '%b%s%b\n' "$GREEN" "$1" "$NC"; }
warn() { printf '%b%s%b\n' "$YELLOW" "$1" "$NC"; }
err()  { printf '%b%s%b\n' "$RED" "$1" "$NC"; }
fail() { err "$1"; exit 1; }

# Escape a value for safe use inside a single-quoted SQL string literal
# (Postgres standard_conforming_strings is on by default: only ' needs doubling)
pg_sql_escape() {
    local s="$1"
    s=${s//\'/\'\'}
    printf '%s' "$s"
}

#------------------------------------------------------------------------------
# Must run as root - the backup cron runs as root and libpq reads
# $HOME/.pgpass by default, so credentials must land in root's HOME.
#------------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || fail "Run this as root (e.g. sudo $0), not as $(whoami)."
info "Running as root. \$HOME is $HOME - .pgpass will be written here."
[ "$HOME" = "/root" ] || warn "\$HOME is not /root - confirm this matches the account the backup cron runs as."

PGPASS_FILE="${PGPASSFILE:-$HOME/.pgpass}"
touch "$PGPASS_FILE"
chmod 600 "$PGPASS_FILE"

FAILED=0

for key in "${!PG_INSTANCES[@]}"; do
    IFS=':' read -r port user desc bin_dir <<< "${PG_INSTANCES[$key]}"
    echo
    info "=== $desc (port $port, role $user) ==="

    PSQL="$bin_dir/psql"
    if [ ! -x "$PSQL" ]; then
        warn "$PSQL not found/executable; falling back to 'psql' from PATH."
        PSQL="psql"
        command -v psql >/dev/null 2>&1 || { err "No usable psql binary for $desc. Skipping."; FAILED=1; continue; }
    fi

    #--------------------------------------------------------------------
    # Ask the server directly (via the "postgres" OS account's locally
    # peer-trusted socket) whether this role already has a password set,
    # rather than guessing from a TCP connection attempt. pg_hba.conf on
    # this host requires scram-sha-256 for ALL TCP connections from
    # 127.0.0.1/::1 (no trust line), so a failed TCP test can't tell us
    # whether that's because there's no password or because we simply
    # didn't supply one.
    #--------------------------------------------------------------------
    ESCAPED_USER=$(pg_sql_escape "$user")
    HAS_PW=$(sudo -iu postgres "$PSQL" -p "$port" -tAc \
        "SELECT rolpassword IS NOT NULL FROM pg_authid WHERE rolname='$ESCAPED_USER'" 2>/dev/null | tr -d '[:space:]')

    if [ -z "$HAS_PW" ]; then
        err "Could not query pg_authid via local peer auth as OS user 'postgres' on port $port (role '$user' may not exist, or 'sudo -iu postgres' failed). Skipping $desc."
        FAILED=1
        continue
    fi

    if [ "$HAS_PW" = "f" ]; then
        info "Role '$user' on port $port has NO password set yet."
        read -rp "Set one now via local peer auth (required for TCP backups under this pg_hba.conf)? [y/N] " SETPW
        if [[ ! "$SETPW" =~ ^[Yy]$ ]]; then
            warn "Leaving '$user' on port $port passwordless. Backups against this instance will fail until a password is set (pg_hba requires scram-sha-256 over TCP)."
            continue
        fi
        read -rsp "New password for $user (port $port): " NEWPW; echo
        read -rsp "Confirm password: " NEWPW2; echo
        [ -n "$NEWPW" ] || { err "Password cannot be empty. Skipping $desc."; FAILED=1; continue; }
        [ "$NEWPW" = "$NEWPW2" ] || { err "Passwords did not match. Skipping $desc."; FAILED=1; continue; }
        ESCAPED_PW=$(pg_sql_escape "$NEWPW")
        if ! sudo -iu postgres "$PSQL" -p "$port" -c "ALTER ROLE \"$user\" WITH PASSWORD '$ESCAPED_PW';" >/dev/null 2>&1; then
            err "Failed to set password via local peer auth as OS user 'postgres'. Skipping $desc."
            unset NEWPW NEWPW2 ESCAPED_PW
            FAILED=1
            continue
        fi
        DB_PASS="$NEWPW"
        unset NEWPW NEWPW2 ESCAPED_PW
        ok "Password set for role '$user' on port $port."
    else
        info "Role '$user' on port $port already has a password set (can't be recovered from the DB, only re-stored)."
        read -rsp "Enter the existing password for $user (port $port): " DB_PASS; echo
        [ -n "$DB_PASS" ] || { err "Password cannot be empty. Skipping $desc."; FAILED=1; continue; }
    fi

    #--------------------------------------------------------------------
    # Write/replace the .pgpass line for this host:port:*:user
    # (database field is * since the backup script loops over every DB)
    #--------------------------------------------------------------------
    ESCAPED_FOR_PGPASS=$(printf '%s' "$DB_PASS" | sed -e 's/\\/\\\\/g' -e 's/:/\\:/g')
    NEWLINE="${PGHOST_FIELD}:${port}:*:${user}:${ESCAPED_FOR_PGPASS}"
    unset DB_PASS ESCAPED_FOR_PGPASS

    grep -v -F "${PGHOST_FIELD}:${port}:*:${user}:" "$PGPASS_FILE" > "${PGPASS_FILE}.tmp" 2>/dev/null || true
    printf '%s\n' "$NEWLINE" >> "${PGPASS_FILE}.tmp"
    mv "${PGPASS_FILE}.tmp" "$PGPASS_FILE"
    chmod 600 "$PGPASS_FILE"
    unset NEWLINE
    ok "Stored credentials for $user@$PGHOST_FIELD:$port in $PGPASS_FILE."

    #--------------------------------------------------------------------
    # Verify: reconnect using ONLY the .pgpass file, no password given directly
    #--------------------------------------------------------------------
    if env -u PGPASSWORD "$PSQL" -h "$PGHOST_FIELD" -p "$port" -U "$user" -d postgres -tAc "SELECT 1" >/dev/null 2>&1; then
        ok "Verified: psql connects to port $port using $PGPASS_FILE with no password flag."
    else
        err "Verification failed for port $port. Check pg_hba.conf allows host connections for '$user' from 127.0.0.1/::1 using md5/scram-sha-256."
        FAILED=1
    fi
done

echo
if [ "$FAILED" -ne 0 ]; then
    fail "One or more instances were not fully configured. See messages above."
fi
ok "All configured instances verified. postgres_backup_multi.sh will now pick up $PGPASS_FILE automatically."
