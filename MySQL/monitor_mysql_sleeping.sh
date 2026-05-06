#!/bin/bash

# ================================================
# MySQL Sleeping Connections Monitor
# Runs every hour via cron and exports sleeping connections to CSV
# ================================================

# ---------------- Configuration -----------------
MYSQL_USER="kiwisql"          # Change to your MySQL user (e.g., root or a monitoring user)
MYSQL_PASS="password"      # Change to your password (better to use ~/.my.cnf for security)
MYSQL_HOST="localhost"                # Usually localhost, or remote host
MYSQL_PORT="3306"

# Output directory (create it with proper permissions)
OUTPUT_DIR="/KIWI/site/bin/mysql_sleeping"
LOG_FILE="${OUTPUT_DIR}/sleeping_connections_$(date +%Y-%m-%d).csv"

# Optional: Only include sleeping connections older than X seconds (0 = all sleeping)
MIN_SLEEP_TIME=60                     # e.g., 60 = only connections sleeping > 1 minute

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# ------------------ Query -----------------------
# Use INFORMATION_SCHEMA for better control (recommended over SHOW PROCESSLIST)
QUERY="
SELECT 
    NOW() AS snapshot_time,
    ID AS thread_id,
    USER,
    HOST,
    DB AS database_name,
    COMMAND,
    TIME AS time_sleeping_seconds,
    STATE,
    INFO AS last_query
FROM information_schema.processlist
WHERE COMMAND = 'Sleep'
  AND TIME >= ${MIN_SLEEP_TIME}
ORDER BY TIME DESC;
"

# Run the query and append to CSV with header only on first run of the day
if [ ! -f "$LOG_FILE" ]; then
    # First run of the day → add header
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" \
        -e "SELECT 'snapshot_time','thread_id','user','host','database_name','command','time_sleeping_seconds','state','last_query';" \
        --batch --silent >> "$LOG_FILE" 2>/dev/null
fi

# Append the actual data
mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" \
    -e "$QUERY" --batch --silent >> "$LOG_FILE" 2>> "${OUTPUT_DIR}/error.log"

# Optional: Log a summary
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Exported sleeping connections to $LOG_FILE" >> "${OUTPUT_DIR}/monitor.log"

# Optional: Keep only last 30 days of logs (uncomment if desired)
# find "$OUTPUT_DIR" -name "sleeping_connections_*.csv" -mtime +30 -delete