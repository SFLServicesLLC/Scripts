#!/usr/bin/env bash
#
# generate_shortcuts_ps1.sh
#
# Reads a Kiwiplan install "summary.log.txt" (the "Web application URLs"
# section) and generates a PowerShell script that creates matching Windows
# desktop shortcuts. Since the log's app list/URLs/server can change from
# one install to the next, this parses the log fresh every run instead of
# hard-coding anything.
#
# Machine-specific URLs (containing a "machine=<x>" placeholder, e.g. the
# PCS Machine Operator Module entry) are expanded into one shortcut per
# machine by querying ${PLANTID}_man.machine for the list of oname values.
# The machine name is wrapped in double quotes inside the URL so machine
# names containing spaces or other special characters survive as a single
# command-line argument when KiwiWebLauncher.exe is launched.
#
# Corrugator-specific URLs (containing a "{x}" placeholder) have no data
# source configured and are still skipped.
#
# Only "Launcher" (KiwiWebLauncher.exe) and "Direct" (opens in default
# browser) shortcuts are created. mshta.exe-based application entries are
# intentionally excluded - where the log lists both an mshta and a
# KiwiWebLauncher variant of the same app, only the Launcher variant is used.
#
# Created by: Steve Ling & claude.ai, 2024-06-05
#
# Usage:
#   ./generate_shortcuts_ps1.sh [path/to/summary.log.txt] [path/to/output.ps1]
#
# Defaults:
#   input  = /KIWI/services/sites/${PLANTID}/current/logs/summary.log.txt
#   output = ./Create-${PLANTID}-KiwiplanShortcuts.ps1
#
# Requires the PLANTID environment variable to be set - it's used to locate
# the default log path, name the output file, name the desktop folder the
# shortcuts are placed in, and pick the ${PLANTID}_man database to query.
#
# Also uses (with defaults, override via environment if needed):
#   KWSQL_USER - mysql user for the machine lookup query
#   MYSQL_PWD  - mysql password for the machine lookup query
#
# The generated .ps1 is meant to be copied to the Windows box and run there.
#

set -euo pipefail

if [[ -z "${PLANTID:-}" ]]; then
    echo "Error: PLANTID environment variable must be set (used for the default log path, output filename, desktop shortcut folder name, and machine lookup database)." >&2
    exit 1
fi

KWSQL_USER=${KWSQL_USER:-kiwisql}
MYSQL_PWD=${MYSQL_PWD:-XXXXX}

LOGFILE="${1:-/KIWI/services/sites/${PLANTID}/current/logs/summary.log.txt}"
OUTFILE="${2:-Create-${PLANTID}-KiwiplanShortcuts.ps1}"

if [[ ! -f "$LOGFILE" ]]; then
    echo "Error: log file not found: $LOGFILE" >&2
    exit 1
fi

# --- Parse "Application: X" / "URL: Y" pairs -------------------------------
# Each pair is two consecutive lines in the "Web application URLs" section.
# Output as App<TAB>Url, one per line.
pairs="$(awk '
    /^Application:/ {
        sub(/^Application:[ \t]*/, "")
        app = $0
        getline
        sub(/^URL:[ \t]*/, "")
        url = $0
        print app "\t" url
    }
' "$LOGFILE")"

if [[ -z "$pairs" ]]; then
    echo "Error: no \"Application:\"/\"URL:\" pairs found in $LOGFILE" >&2
    exit 1
fi

# --- Machine lookup (lazy - only queried if a machine=<x> URL is seen) -----

machines=()
machines_fetched=0

fetch_machines() {
    if [[ $machines_fetched -eq 1 ]]; then
        return
    fi
    machines_fetched=1

    if ! command -v mysql >/dev/null 2>&1; then
        echo "Warning: mysql client not found in PATH - machine-specific (machine=<x>) shortcuts will be skipped." >&2
        return
    fi

    local db="${PLANTID}_man"
    local err_file
    err_file="$(mktemp)"
    local result

    if ! result="$(mysql -u"$KWSQL_USER" -p"$MYSQL_PWD" -N -B -e "SELECT oname FROM ${db}.machine" 2>"$err_file")"; then
        echo "Warning: mysql query against ${db}.machine failed - machine-specific shortcuts will be skipped." >&2
        sed 's/^/  mysql: /' "$err_file" >&2
        rm -f "$err_file"
        return
    fi
    rm -f "$err_file"

    while IFS= read -r line; do
        line="$(printf '%s' "$line" | sed -e 's/\r$//')"
        [[ -n "$line" ]] && machines+=("$line")
    done <<< "$result"

    if [[ ${#machines[@]} -eq 0 ]]; then
        echo "Warning: no rows returned from ${db}.machine - machine-specific shortcuts will be skipped." >&2
    fi
}

# --- Build the $apps array lines + collect skipped/removed apps -----------
apps_ps1=""
skipped_lines=""
removed_lines=""
app_count=0
skip_count=0
removed_count=0

# Classifies one app/url pair (with any placeholder already resolved) and
# appends the corresponding PowerShell hashtable entry to $apps_ps1.
# Only Launcher (KiwiWebLauncher.exe) and Direct (default browser) apps
# are supported - mshta.exe entries are filtered out before this is called.
emit_app_entry() {
    local app="$1"
    local url="$2"
    local app_esc url_esc real_url real_url_esc

    app_esc="${app//\"/\`\"}"
    url_esc="${url//\"/\`\"}"

    if [[ "$url" == *"KiwiWebLauncher.exe -u "* ]]; then
        real_url="${url#*KiwiWebLauncher.exe -u }"
        real_url_esc="${real_url//\"/\`\"}"
        apps_ps1+="    @{ Name = \"${app_esc}\"; Type = \"Launcher\"; Url = \"${real_url_esc}\" }"$'\n'
    elif [[ "$url" == http* ]]; then
        apps_ps1+="    @{ Name = \"${app_esc}\"; Type = \"Direct\"; Url = \"${url_esc}\" }"$'\n'
    else
        # Unrecognized URL shape - keep it, default to Direct, flag with a comment
        apps_ps1+="    @{ Name = \"${app_esc}\"; Type = \"Direct\"; Url = \"${url_esc}\" } # NOTE: unrecognized URL format, verify manually"$'\n'
    fi

    app_count=$((app_count + 1))
}

while IFS=$'\t' read -r app url; do
    [[ -z "$app" ]] && continue

    # Trim any trailing carriage return / whitespace (CRLF-safe)
    app="$(printf '%s' "$app" | sed -e 's/\r$//' -e 's/[[:space:]]*$//')"
    url="$(printf '%s' "$url" | sed -e 's/\r$//' -e 's/[[:space:]]*$//')"

    # mshta.exe entries are intentionally excluded - only Launcher shortcuts
    # are created (see the module header for why).
    if [[ "$url" == *"mshta.exe "* ]]; then
        removed_lines+=$'\n'"#   - ${app}: ${url}"
        removed_count=$((removed_count + 1))
        continue
    fi

    # Corrugator-style placeholder ({x}) - no data source configured, skip.
    if [[ "$url" == *"{x}"* ]]; then
        skipped_lines+=$'\n'"#   - ${app}: ${url}"
        skip_count=$((skip_count + 1))
        continue
    fi

    # Machine-style placeholder (<x>) - expand into one shortcut per machine,
    # using the oname values from ${PLANTID}_man.machine. The machine name
    # is wrapped in double quotes so spaces/special characters in it survive
    # as a single command-line argument.
    if [[ "$url" == *"<x>"* ]]; then
        fetch_machines
        if [[ ${#machines[@]} -eq 0 ]]; then
            skipped_lines+=$'\n'"#   - ${app}: ${url} (no machines returned from ${PLANTID}_man.machine)"
            skip_count=$((skip_count + 1))
            continue
        fi
        for m in "${machines[@]}"; do
            quoted_m="\"${m}\""
            emit_app_entry "${app} - ${m}" "${url//<x>/$quoted_m}"
        done
        continue
    fi

    emit_app_entry "$app" "$url"
done <<< "$pairs"

if [[ -z "$skipped_lines" ]]; then
    skipped_lines=$'\n'"#   (none)"
fi

if [[ -z "$removed_lines" ]]; then
    removed_lines=$'\n'"#   (none)"
fi

generated_stamp="$(date '+%Y-%m-%d %H:%M:%S')"
source_log_line="$(grep -m1 '^Date:' "$LOGFILE" || true)"

# --- Emit the .ps1 file ------------------------------------------------------

{
cat <<HEADER
<#
.SYNOPSIS
    Creates Windows desktop shortcuts (.lnk) for the Kiwiplan / Bor
    applications listed in the install log.

.DESCRIPTION
    Auto-generated by generate_shortcuts_ps1.sh on ${generated_stamp}
    from: ${LOGFILE}
    Log ${source_log_line:-"date: (not found in log)"}

    DO NOT hand-edit this file - it is regenerated from summary.log.txt
    each time the generator script runs. Edit summary.log.txt (or the
    generator script) instead, then regenerate.

    Shortcuts are placed in a "${PLANTID}" subfolder on the desktop
    (created automatically if it doesn't exist), so multiple plants'
    shortcuts don't collide or get mixed together.

    Two kinds of shortcuts are created:
      1. "Launcher" apps - opened via KiwiWebLauncher.exe -u <url>
      2. "Direct" apps    - opened straight in the default browser

    Machine-specific applications (URLs containing a "machine=<x>"
    placeholder) were expanded into one shortcut per machine, using the
    oname values returned by:
      SELECT oname FROM ${PLANTID}_man.machine
    The machine name is wrapped in double quotes in the resulting URL so
    names containing spaces survive as a single command-line argument.

    ${removed_count} application(s) were intentionally excluded because
    they use mshta.exe rather than KiwiWebLauncher.exe - only the Launcher
    variant of each app is kept:
${removed_lines}

    ${skip_count} application(s) from the log were skipped because their
    URL requires a runtime parameter that couldn't be resolved (a
    corrugator id shown as "{x}" with no data source configured, or a
    machine id where the database lookup returned nothing):
${skipped_lines}

.PARAMETER PublicDesktop
    Force shortcuts onto the server's Public Desktop (C:\Users\Public\Desktop)
    instead of the current user's desktop. Useful when this script is run
    non-interactively (e.g. as a scheduled task or service account) so the
    shortcuts land somewhere every logged-in user can actually see them.

.NOTES
    - Run this script ON THE WINDOWS MACHINE (PowerShell, not WSL/bash).
    - Requires the KIWI_WEB_PATH environment variable to be set on the
      machine, OR edit \$KiwiWebLauncherPath below to point directly at
      KiwiWebLauncher.exe.
    - Shortcuts are placed in a "${PLANTID}" folder, created automatically
      if needed, under one of:
        * the current user's desktop (default, interactive use), or
        * the server's Public Desktop - used automatically when no
          interactive user desktop is available (e.g. running as SYSTEM/a
          service account on the server), or always when -PublicDesktop
          is passed.
    - Run like this for public desktop icons (e.g. scheduled task, service account, or non-interactive use):
        powershell.exe -ExecutionPolicy Bypass -File Create-${PLANTID}-KiwiplanShortcuts.ps1 -PublicDesktop
#>

[CmdletBinding()]
param(
    [switch]\$PublicDesktop
)

# ----------------------------- Configuration -----------------------------

\$PlantId = "${PLANTID}"
\$PublicDesktopPath = "C:\Users\Public\Desktop"

# Shortcuts go in <Desktop>\<PlantId>\ instead of directly on the desktop,
# so shortcuts for multiple plants don't collide or get mixed together.
# Resolve which desktop root to use: the current user's desktop, unless
# -PublicDesktop was passed, or no interactive user desktop is available
# (e.g. this is running as SYSTEM/a service account on the server).
if (\$PublicDesktop) {
    \$DesktopRoot = \$PublicDesktopPath
} else {
    \$userDesktop = [Environment]::GetFolderPath("Desktop")
    \$noInteractiveDesktop = ([string]::IsNullOrWhiteSpace(\$userDesktop)) -or
        (\$userDesktop -like "*systemprofile*") -or
        (\$userDesktop -like "*ServiceProfiles*") -or
        (-not (Test-Path (Split-Path \$userDesktop -Parent)))

    if (\$noInteractiveDesktop) {
        Write-Host "No interactive user desktop detected (running as \$env:USERNAME) - using the Public Desktop instead."
        \$DesktopRoot = \$PublicDesktopPath
    } else {
        \$DesktopRoot = \$userDesktop
    }
}

\$DesktopPath = Join-Path \$DesktopRoot \$PlantId

if (-not (Test-Path \$DesktopPath)) {
    New-Item -ItemType Directory -Path \$DesktopPath -Force | Out-Null
    Write-Host "Created folder: \$DesktopPath"
}

# Path to KiwiWebLauncher.exe - resolved from %KIWI_WEB_PATH% at run time.
# If KIWI_WEB_PATH isn't set as an environment variable on this machine,
# replace the line below with a hard-coded path, e.g.:
# \$KiwiWebLauncherPath = "C:\Kiwiplan\WebLauncher\KiwiWebLauncher.exe"
\$KiwiWebLauncherPath = Join-Path ([Environment]::GetEnvironmentVariable("KIWI_WEB_PATH")) "KiwiWebLauncher.exe"

# --------------------------- Application list -----------------------------
# Parsed from ${LOGFILE} - ${app_count} app(s) (machine-specific URLs expanded per machine)

\$apps = @(
HEADER

printf '%s' "$apps_ps1"

cat <<'FOOTER'
)

# ------------------------------ Shortcut creation ---------------------------

$wshShell = New-Object -ComObject WScript.Shell
$invalidChars = [System.IO.Path]::GetInvalidFileNameChars()

foreach ($app in $apps) {

    # Shortcut names can be built from a database value (machine oname), so
    # strip any character that isn't valid in a Windows file name.
    $safeName = -join ($app.Name.ToCharArray() | ForEach-Object { if ($invalidChars -contains $_) { '_' } else { $_ } })

    $shortcutPath = Join-Path $DesktopPath ("$safeName.lnk")
    $shortcut = $wshShell.CreateShortcut($shortcutPath)

    switch ($app.Type) {

        "Launcher" {
            if (-not (Test-Path $KiwiWebLauncherPath)) {
                Write-Warning "KiwiWebLauncher.exe not found at '$KiwiWebLauncherPath' - shortcut for '$($app.Name)' created anyway, but verify KIWI_WEB_PATH."
            }
            $shortcut.TargetPath = $KiwiWebLauncherPath
            $shortcut.Arguments  = "-u $($app.Url)"
            $shortcut.WorkingDirectory = Split-Path $KiwiWebLauncherPath
        }

        "Direct" {
            # A .lnk whose target is a URL launches the default browser
            $shortcut.TargetPath = $app.Url
        }
    }

    $shortcut.Description = $app.Name
    $shortcut.Save()

    Write-Host "Created: $shortcutPath"
}

Write-Host "`nDone. $($apps.Count) shortcut(s) created in $DesktopPath."
FOOTER
} > "$OUTFILE"

echo "Parsed $app_count application(s) (after machine expansion), skipped $skip_count unresolved parameterized app(s), excluded $removed_count mshta app(s)."
echo "Wrote: $OUTFILE"
