#!/bin/bash
#==============================================================================
#TITLE:        setup_mysql_login.sh
#DESCRIPTION:  Sets up credentials for mysql_backup.sh to use, equivalent to
#              postgres' ~/.pgpass. Prefers the encrypted ~/.mylogin.cnf
#              (via mysql_config_editor); falls back to a chmod 600
#              ~/.my.cnf if mysql_config_editor isn't installed.
#
#              Also handles the case where the DB user has no password set
#              yet (common right after install: auth_socket/unix_socket
#              plugin, or a blank password) by offering to set one.
#
#AUTHOR:       Steve Ling
#USAGE:        sudo ./setup_mysql_login.sh [db_user] [db_host]
#              db_user defaults to "root", db_host defaults to "localhost"
#==============================================================================

set -uo pipefail

DB_USER="${1:-root}"
DB_HOST="${2:-localhost}"
LOGIN_PATH="client"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

info() { printf '%b%s%b\n' "$CYAN" "$1" "$NC"; }
ok()   { printf '%b%s%b\n' "$GREEN" "$1" "$NC"; }
warn() { printf '%b%s%b\n' "$YELLOW" "$1" "$NC"; }
fail() { printf '%b%s%b\n' "$RED" "$1" "$NC"; exit 1; }

# Escape a value for safe use inside a single-quoted SQL string literal
sql_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\'/\\\'}"
    printf '%s' "$s"
}

#------------------------------------------------------------------------------
# 1. Must run as root - the backup cron runs as root and reads $HOME/.my.cnf
#    or $HOME/.mylogin.cnf, so credentials must be written to root's HOME.
#------------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || fail "Run this as root (e.g. sudo $0), not as $(whoami)."
info "Running as root. \$HOME is $HOME - credentials will be written here."
[ "$HOME" = "/root" ] || warn "\$HOME is not /root - confirm this matches the account the backup cron runs as."

#------------------------------------------------------------------------------
# 2. Locate the mysql/mariadb client
#------------------------------------------------------------------------------
if command -v mysql >/dev/null 2>&1; then
    PROG="mysql"
elif command -v mariadb >/dev/null 2>&1; then
    PROG="mariadb"
else
    fail "Neither 'mysql' nor 'mariadb' command found in PATH."
fi
info "Using '$PROG' client for $DB_USER@$DB_HOST."

#------------------------------------------------------------------------------
# 3. Check whether mysql_config_editor is available (ships with MySQL's
#    client package; some MariaDB-only hosts don't have it)
#------------------------------------------------------------------------------
if command -v mysql_config_editor >/dev/null 2>&1; then
    USE_FALLBACK=0
else
    warn "mysql_config_editor not found (common on MariaDB-only installs)."
    warn "Falling back to a plaintext ~/.my.cnf instead."
    USE_FALLBACK=1
fi

#------------------------------------------------------------------------------
# 4. Check whether $DB_USER can already connect with NO password. If so,
#    it's likely using auth_socket/unix_socket auth or has a blank password.
#------------------------------------------------------------------------------
if "$PROG" -u "$DB_USER" -h "$DB_HOST" -e "SELECT 1" >/dev/null 2>&1; then
    ok "$DB_USER@$DB_HOST already connects with no password (socket auth or blank password)."
    read -rp "Set a password for $DB_USER now so backups don't depend on socket-only auth? [y/N] " SETPW
    if [[ "$SETPW" =~ ^[Yy]$ ]]; then
        read -rsp "New password for $DB_USER: " NEWPW; echo
        read -rsp "Confirm password: " NEWPW2; echo
        [ -n "$NEWPW" ] || fail "Password cannot be empty."
        [ "$NEWPW" = "$NEWPW2" ] || fail "Passwords did not match."
        ESCAPED_PW=$(sql_escape "$NEWPW")
        "$PROG" -u "$DB_USER" -h "$DB_HOST" -e \
            "ALTER USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$ESCAPED_PW';" \
            || fail "Failed to set password for $DB_USER@$DB_HOST."
        ok "Password set for $DB_USER@$DB_HOST."
        unset NEWPW NEWPW2 ESCAPED_PW
        NEEDS_STORE=1
    else
        info "Leaving $DB_USER@$DB_HOST passwordless."
        info "No credentials file is needed - mysql_backup.sh will connect via default (socket) authentication."
        exit 0
    fi
else
    info "$DB_USER@$DB_HOST requires a password to connect."
    NEEDS_STORE=1
fi

#------------------------------------------------------------------------------
# 5. Store the credentials so mysql/mysqldump pick them up automatically
#------------------------------------------------------------------------------
if [ "$USE_FALLBACK" -eq 1 ]; then
    MY_CNF="$HOME/.my.cnf"
    read -rsp "Password for $DB_USER@$DB_HOST to store in $MY_CNF: " DB_PASS; echo
    [ -n "$DB_PASS" ] || fail "Password cannot be empty."
    umask 077
    cat > "$MY_CNF" <<EOF
[client]
user=$DB_USER
host=$DB_HOST
password=$DB_PASS
EOF
    chmod 600 "$MY_CNF"
    unset DB_PASS
    ok "Wrote $MY_CNF (mode $(stat -c '%a' "$MY_CNF"))."
else
    info "Enter the password for $DB_USER@$DB_HOST when prompted below."
    mysql_config_editor set --login-path="$LOGIN_PATH" --host="$DB_HOST" --user="$DB_USER" --password \
        || fail "mysql_config_editor failed to save credentials."
    chmod 600 "$HOME/.mylogin.cnf" 2>/dev/null
    ok "Saved encrypted credentials to $HOME/.mylogin.cnf (login-path: $LOGIN_PATH)."
    mysql_config_editor print --all
fi

#------------------------------------------------------------------------------
# 6. Verify the stored credentials actually work, with no -u/-p flags
#------------------------------------------------------------------------------
info "Verifying connection using stored credentials..."
if "$PROG" -e "SELECT 1" >/dev/null 2>&1; then
    ok "Success: '$PROG' now connects using stored credentials with no -u/-p flags."
    info "mysql_backup.sh will pick this up automatically via \$HOME/.my.cnf or \$HOME/.mylogin.cnf."
else
    fail "Verification failed: '$PROG' could not connect using the stored credentials."
fi
