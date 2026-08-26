#!/bin/bash

# Purpose: Verify and manage VUE application errors and data intergrity
VERSION=2.7.0
# Author : Steven F Ling
# Credits for some of the scripts : Randolph Domingo, Devops Teams
# Created: 2025-09-23
# Updated: 2025-09-24
# Updated: 2025-11-09
# Updated: 2026-04-05
# Updated: 2026-08-21-23
# Updated: 2026-08-24 - Added GitHub version check
# Updated: 2026-08-24 - Email this run's log via sendmail on completion
# Updated: 2026-08-25 - Fixed display_step_details() (empty-db mysql failures, broken $PROCESSID_x.tm temp files, simplified O(n^2) loops)
# Updated: 2026-08-25 - handle_order_action() no longer runs UPDATE statements; now logs the recommended fix for a human to apply
# Updated: 2026-08-25 - Added recommend_job_fixes() to auto-detect and report close/open/run fixes for jobs with bad data

# Define color codes
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'
FLASH='\033[5m'

# Logging configuration
LOG_FOLDER="/KIWI/corp/bin/"
LOG_FILE="checkord.log"	# Log File
MAX_LOG_SIZE=$((1*1024*1024)) 			# 1MB
LOG_DIR=$(dirname "$LOG_FILE")			# Path of logging directory
PROCESSID=$(date +%Y%m%d_%k%M%S)        # Your own process ID

# Email report configuration
: "${MAILTO:=}"		# Who receives the health check report separate with comma
RUN_LOG_START=1
if [ -f "$LOG_FILE" ]; then
    RUN_LOG_START=$(( $(wc -l < "$LOG_FILE") + 1 ))
fi

# Database credentials
: "${DEBUG:=N}"					                                        # Debug Mode
#: "${PLANTID:?Error: PLANTID is not supplied}"	                        # Dataset plantcode
: "${PLANTID:=$PLANTID}"			                                    # Dataset plantcode
: "${MYSQL_HOST:=localhost}"		                                    # MySQL host
: "${MYSQL_USER:=$(grep "USER=" $DATA/kwsql|cut -d"=" -f2)}"			# MySQL username
: "${MYSQL_PASSWORD:=$(grep "PASSWORD=" $DATA/kwsql|cut -d"=" -f2-)}"	# MySQL password
: "${ORDERNUMBER:=}"				                                    # Order Number to use
: "${ORDERID:=}"				                                        # Order ID to use
: "${JOBID:=}"					                                        # Job ID to use
: "${KIWIBASE:=/opt/kiwi}"                                               # Kiwiplan base directory
# Update check configuration
REPO_RAW_URL="https://raw.githubusercontent.com/SFLServicesLLC/Scripts/main/Kiwiplan/checkVUEHealthy.sh"
REPO_URL="https://github.com/SFLServicesLLC/Scripts/blob/main/Kiwiplan/checkVUEHealthy.sh"

# VUE Log Path
VUE_LOG_PATH="/${KIWIBASE}/services/sites/${PLANTID}/current/logs"

# Function to handle logging
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Log to console with color
    case "$level" in
        "INFO")
            echo -e "${GREEN}[$timestamp] [INFO] $message${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [WARN] $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp] [ERROR] $message${NC}"
            ;;
    esac
}

# Function to execute MySQL query with error handling
execute_mysql_query() {
    local query="$1"
    local db="$2"
    local result
    result=$(MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$db" -e "$query" 2>/dev/null | tail -n +2)
    if [ $? -ne 0 ]; then
        log_message "ERROR" "MySQL query failed: $query"
        return 1
    fi
    echo "$result"
    return 0
}

# Ensure KIWIWBASE exists
check_kiwibase() {
    if [ ! -d "$KIWIBASE" ]; then
        log_message "ERROR" "${RED}##################################################################################################${NC}"
        log_message "ERROR" "${RED}KIWIBASE directory $KIWIBASE does not exist${NC}"
        exit 1
    else
        log_message "INFO" "${GREEN}##################################################################################################${NC}"
        log_message "INFO" "${CYAN}KIWIBASE directory $KIWIBASE exists${NC}"
    fi
}

# Function to rotate log file
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ "$(stat -c %s "$LOG_FILE" 2>/dev/null || stat -f %z "$LOG_FILE")" -ge "$MAX_LOG_SIZE" ]; then
        log_message "INFO" "${YELLOW}##################################################################################################${NC}"
        log_message "INFO" "${YELLOW}Log file size exceeded $MAX_LOG_SIZE bytes, rotating log${NC}"
        mv "$LOG_FILE" "${LOG_FILE}.$(date '+%Y%m%d%H%M%S')"
        touch "$LOG_FILE"
        log_message "INFO" "${CYAN}Log file rotated due to size exceeding $MAX_LOG_SIZE bytes"
    fi
}

# Check to see if the PLANTID variable exists
check_plantid() {
    local var_name="$1"
    local var_value="${!var_name}"
    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    log_message "INFO" "${CYAN}Current version is: $VERSION${NC}"
    

    if [ -z "$PLANTID" ]; then
        log_message "ERROR" "${RED}##################################################################################################${NC}"
        log_message "ERROR" "${RED}$PLANTID is not setup or supplied.${NC}"
        USAGE="PLANTID=maxco"
        EXAMPLE="PLANTID=maxco $0"
        USAGEDESC="This is a manditory field"
            usage
        exit 1
    else
        log_message "INFO" "${GREEN}##################################################################################################${NC}"
        log_message "INFO" "${CYAN}$var_name is set to $var_value${NC}"
    fi
    
}

# Ensure log directory exists
create_folders() {
    if [ ! -d "$LOG_FOLDER" ];then
        log_message "INFO" "${YELLOW}##################################################################################################${NC}"
        log_message "INFO" "${YELLOW}Creating log folder $LOG_FOLDER${NC}"
        mkdir -p "$LOG_FOLDER"
    else
        log_message "INFO" "${GREEN}##################################################################################################${NC}"
        log_message "INFO" "${GREEN}Log folder $LOG_FOLDER exists${NC}"
    fi
}

#Get dataset enviroment information
get_environment() {

    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    log_message "INFO" "${CYAN}Getting dataset enviroment information${NC}"
    PORTS=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep OFFSET|cut -d"=" -f2)
    CLASSIC=$(grep "DATA=" $DATA/kwsql|cut -d"=" -f2)
    CSC_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.CSC_DBNAME|cut -d"=" -f2)
    PCS_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.PCS_DBNAME|cut -d"=" -f2)
    MAN_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.MANUFACTURING_DBNAME|cut -d"=" -f2)
    MANUF_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.MANUFACTURING_CLASSIC_DBNAME|cut -d"=" -f2)
    MMS_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.MATERIAL_MANAGEMENT_DBNAME|cut -d"=" -f2)
    QMS_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.QUALITY_DBNAME|cut -d"=" -f2)
    TSS_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.TSS_DBNAME|cut -d"=" -f2)
    PIC_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.PICS_DBNAME|cut -d"=" -f2)
    PSL_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.LOCATION_COMMON_DBNAME|cut -d"=" -f2)
    SUP_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.SUPPLIER_MANAGEMENT_DBNAME|cut -d"=" -f2)

}

# Function to email this run's log as an attachment via sendmail/Postfix
send_report_email() {
    local run_log="/tmp/${PLANTID}_${PROCESSID}_checkord_run.log"
    tail -n +"$RUN_LOG_START" "$LOG_FILE" | sed -r 's/[\\]033\[[0-9;]*m//g' > "$run_log"

    local subject="Check Health $PLANTID $HOSTNAME"
    local boundary="====${PROCESSID}===="

    {
        echo "To: $MAILTO"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary=\"$boundary\""
        echo
        echo "--$boundary"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo
        echo "Check Health $HOSTNAME"
        echo
        echo "--$boundary"
        echo "Content-Type: text/plain; name=\"$(basename "$run_log")\""
        echo "Content-Disposition: attachment; filename=\"$(basename "$run_log")\""
        echo "Content-Transfer-Encoding: base64"
        echo
        base64 "$run_log"
        echo
        echo "--$boundary--"
    } | sendmail -t

    rm -f "$run_log"
}

# Function to display usage message
usage() {
    local script_name=$(basename "$0")
    log_message "INFO" "${CYAN}Usage: $USAGE $script_name${NC}"
    log_message "INFO" "${CYAN}Example: $EXAMPLE $script_name${NC}"
    log_message "INFO" "${CYAN}Description: $USAGEDESC $script_name${NC}"
}

# Function to check if command exists
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_message "ERROR" "Required command $cmd not found"
        exit 1
    fi
}

# Function to check GitHub for a newer version of this script
check_for_updates() {
    if ! command -v curl &>/dev/null; then
        log_message "WARN" "${YELLOW}##################################################################################################${NC}"
        log_message "WARN" "${YELLOW}curl not found, skipping update check${NC}"
        return
    fi

    local remote_version
    remote_version=$(curl -fsS --max-time 10 "$REPO_RAW_URL" 2>/dev/null | grep -m1 '^VERSION=' | cut -d'=' -f2)

    if [ -z "$remote_version" ]; then
        log_message "WARN" "${YELLOW}##################################################################################################${NC}"
        log_message "WARN" "${YELLOW}Unable to check for updates (could not reach $REPO_RAW_URL)${NC}"
        return
    fi

    if [ "$remote_version" != "$VERSION" ] && [ "$(printf '%s\n%s\n' "$VERSION" "$remote_version" | sort -V | tail -n1)" == "$remote_version" ]; then
        log_message "WARN" "${YELLOW}##################################################################################################${NC}"
        log_message "WARN" "${YELLOW}A newer version of this script is available: $remote_version (currently running $VERSION)${NC}"
        log_message "WARN" "${CYAN}   $REPO_URL${NC}"
        log_message "WARN" "${YELLOW}##################################################################################################${NC}"
    else
        log_message "INFO" "${GREEN}Script is up to date (version $VERSION)${NC}"
    fi
}

# Notes for the User
notes(){

    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    log_message "INFO" "${GREEN}Debug Mode, run the script like this${NC}"
    log_message "INFO" "    ${CYAN}DEBUG=Y $0 ${NC}"
    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    log_message "INFO" "${YELLOW}USAGE to look at machines feedback, run the script like this${NC}"
    log_message "INFO" "    ${CYAN}ORDERNUMBER=[ordernumber] $0 ${NC}"
    log_message "INFO" "    ${CYAN}ORDERID=[orderId] $0 ${NC}"
    log_message "INFO" "    ${CYAN}JOBID=[jobId] $0 ${NC}"
    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    log_message "INFO" "${GREEN}These are Notes worthy tools to know${NC}"
    log_message "INFO" "    ${CYAN}Looking at core dump files for the back trace/call stack${NC}"
    log_message "INFO" "    ${YELLOW}     gdb <path/to/executable> <path/to/corefile>${NC}"
    log_message "INFO" "    ${YELLOW}     Commands to use: bt, bt full${NC}"
    log_message "INFO" "${GREEN}end of Notes${NC}"

}

# Server Drive Space Info
drivespace() {

    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    local load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || log_message "Error: Failed to read load average")
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || log_message "Error: Failed to read disk usage")
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | cut -d. -f1 2>/dev/null || log_message "Error: Failed to read CPU usage")
    local mem_usage=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}' 2>/dev/null || log_message "Error: Failed to read memory usage")
    local type_name=$(grep '^NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local type_version=$(grep '^VERSION=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local mysql_version=$(mysql --version)
    local java_version=$(java -version 2>&1 | head -n 1)
    log_message "INFO" "${GREEN}Server information${NC}"
    log_message "INFO" "    ${CYAN}OS Name :                $type_name${NC}"
    log_message "INFO" "    ${CYAN}OS Version :             $type_version${NC}"
    log_message "INFO" "    ${CYAN}MySQL Version :          $mysql_version${NC}"
    log_message "INFO" "    ${CYAN}Java Version :           $java_version${NC}"
    log_message "INFO" "    ${CYAN}Load on the server :     $load %${NC}"
    log_message "INFO" "    ${CYAN}Total disk usage :       $disk_usage %${NC}"
    log_message "INFO" "    ${CYAN}CPU usage :              $cpu_usage %${NC}"
    log_message "INFO" "    ${CYAN}Memory usage :           $mem_usage %${NC}"
    log_message "INFO" "${GREEN}end of information${NC}"
    
}

# Kiwiplan Software Info
kiwiplan() {

    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    local MAP_REV=$(dirname $(readlink -f ${PROGS}))
    local VUE_REV=$(readlink $KIWIBASE/services/sites/"$PLANTID"/current | sed "s|.*/||")
    log_message "INFO" "${GREEN}Kiwiplan information${NC}"
    log_message "INFO" "    ${CYAN} Classic MAP Rev :   $MAP_REV${NC}"
    log_message "INFO" "    ${CYAN} VUE Rev :           $VUE_REV${NC}"
    log_message "INFO" "${GREEN}end of information${NC}"

}

# Get system logs
get_systemd(){

    journalctl -b &> $LOG_FOLDER/logs_since_boot.txt
    journalctl -b -1 &> $LOG_FOLDER/logs_since_last_boot.txt
    journalctl -p err &> $LOG_FOLDER/err_logs.txt
    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    log_message "INFO" "${GREEN}## We have sent server journal logs if they are needed ##${NC}"
    log_message "INFO" "${CYAN}    Boot Logs:              $LOG_FOLDER/logs_since_boot.txt${NC}"
    log_message "INFO" "${CYAN}    Since Last Boot Logs:   $LOG_FOLDER/logs_since_last_boot.txt${NC}"
    log_message "INFO" "${CYAN}    Error Logs:             $LOG_FOLDER/err_logs.txt${NC}"
}

# Function to check the heatlh of CSC
health_check_csc_order() {
    if [ -z "$CSC_DB" ];then
        log_message "INFO" "${CYAN}CSC Is not Installed${NC}"
        return
    else
        log_message "INFO" "${GREEN}Starting CCS verification tasks${NC}"
        
        log_message "INFO" "${YELLOW}Verifying CSC orders that have a NULL in the corrugator field in the $CSC_DB dB${NC}"
        local corrugatornullcheck
        corrugatornullcheck=$(execute_mysql_query "select count(*) from $CSC_DB.corrugatororder where corrugator is null;") || nullcorrugator="${GREEN}NoErrorsFound${NC}"
        if [[ $corrugatornullcheck -ne 0 ]];then
            local jobnullcorrugator
            jobnullcorrugator=$(execute_mysql_query "select RPAD(COALESCE(orderjobnumber,''),20,' ') from $CSC_DB.corrugatororder where corrugator is null;") || jobnullcorrugator="${CYAN}NoErrorsFound${NC}"
            echo -e "${RED}JobNumber${NC}" | expand -t10
            echo "$jobnullcorrugator" > $PROCESSID_jobnullcorrugator.tm
            cat $PROCESSID_jobnullcorrugator.tm
            log_message "ERROR" "${RED}##################################################################################################${NC}"
            log_message "ERROR" "${RED}These should be fixed as this cause CSC issues${NC}"
            log_message "ERROR" "${RED}##To fix the error NOTE: replace the [CorrugatorNumber] and the [JobNumber] with correct values ##${NC}"
            log_message "ERROR" "${CYAN}   UPDATE corrugatororder SET corrugator = [CorrugatorNumber] WHERE orderjobnumber = '[JobNumber]';${NC}"
            log_message "ERROR" "${RED}##################################################################################################${NC}"
        fi
        log_message "INFO" "${GREEN}Completed verifying CSC orders that have a NULL in the corrugator field in the $CSC_DB dB${NC}"

        log_message "INFO" "${YELLOW}Verifying CSC order/setups that have a NULL in the ActualWidth field in the $CSC_DB & $MAN_DB dB${NC}"
        local widthnullcheck
        widthnullcheck=$(execute_mysql_query "SELECT count(*) 
            FROM $CSC_DB.setupconfiguration sc 
            INNER JOIN $CSC_DB.setuporder so 
            ON so.setupConfiguration = sc.objid 
            INNER JOIN $CSC_DB.corrugatororder co 
            ON so.corrugatorOrder = co.objid 
            INNER JOIN $CSC_DB.setuprun sr 
            ON sr.setupConfiguration = sc.objid 
            INNER JOIN $MAN_DB.job j 
            ON co.jobId = j.objid 
            INNER JOIN $MAN_DB._order o 
            ON j._order = o.objid  
            WHERE sr.status in ('XMIT', 'ISSU', 'UNIS') AND actualWidth is null;") || widthnullcheck="${CYAN}NoErrorsFound${NC}"
        if [[ $widthnullcheck -ne 0 ]];then
            local widthnullcorrugator
            widthnullcorrugator=$(execute_mysql_query "SELECT co.objid, RPAD(COALESCE(co.orderJobNumber,''),20,' '),'fixBadSetups.sh' 
            FROM $CSC_DB.setupconfiguration sc 
            INNER JOIN $CSC_DB.setuporder so 
            ON so.setupConfiguration = sc.objid 
            INNER JOIN $CSC_DB.corrugatororder co 
            ON so.corrugatorOrder = co.objid 
            INNER JOIN $CSC_DB.setuprun sr 
            ON sr.setupConfiguration = sc.objid 
            INNER JOIN $MAN_DB.job j 
            ON co.jobId = j.objid 
            INNER JOIN $MAN_DB._order o 
            ON j._order = o.objid  
            WHERE sr.status in ('XMIT', 'ISSU', 'UNIS') AND actualWidth is null;") || widthnullcorrugator="${CYAN}NoErrorsFound${NC}"
            echo -e "${RED}ObjId\tJobNumber\tUpdate Command Fix${NC}" | expand -t10,30,50
            echo "$widthnullcorrugator" > $PROCESSID_widthcorrugator.tm
            cat $PROCESSID_widthnullcorrugator.tm
        fi
        log_message "INFO" "${GREEN}Completed verifying CSC order/setups that have a NULL in the ActualWidth field in the $CSC_DB & $MAN_DB dB${NC}"

        log_message "INFO" "${YELLOW}Verifying CSC with incorrect weight(s) in the $CSC_DB, $MAN_DB & $PCS_DB dB${NC}"
        local weightcorrugatorcheck
        weightcorrugatorcheck=$(execute_mysql_query "SELECT count(*)
            FROM $MAN_DB._order o
            INNER JOIN $MAN_DB.job jb ON jb._order = o.objid AND jb.retired = 0
            INNER JOIN $PCS_DB.step s ON s.orderNumber = o.orderNumber AND s.jobId = jb.objid AND s.retired = 0
            INNER JOIN $PCS_DB.lineupentry l ON l.step = s.objid
            INNER JOIN $MAN_DB.machine m ON m.objid = l.pcsMachine 
            INNER JOIN $CSC_DB.corrugatororder co ON co.jobId = jb.objid and co.retired = 0 
            INNER JOIN $MAN_DB.materialmaster mm ON mm.objid = co.orderedBoardMasterId
            WHERE round((s.exitBoardArea * (mm.paperDensity + mm.starchDensity)) / 10000000000,0) <> COALESCE(s.exitBoardWeight,0) 
            AND s.stepNumber = 1 AND co.orderStatus NOT IN('BOARD_PRODUCED')
            -- AND o.orderNumber = '7178129030'
            ORDER BY o.orderNumber, jb.jobNumber, s.stepNumber;") || weightcorrugatorcheck="${CYAN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}Total records with incorrect weight(s) in the $CSC_DB, $MAN_DB & $PCS_DB dB${NC}"
            log_message "INFO" "${CYAN}$weightcorrugatorcheck To see all run DEBUG mode${NC}"
        fi
        
        if [[ $weightcorrugatorcheck -ne 0 && $DEBUG == "Y" ]];then
            local weightcorrugator
            weightcorrugator=$(execute_mysql_query "SELECT #s.objid StepId,
            o.orderNumber, co.orderStatus #, jb.jobNumber series, s.stepNumber, m.machineNumber, s.operationSource
            , mm.oname #, (mm.paperDensity + mm.starchDensity) board_density, s.entryBoardArea
            , s.entryBoardWeight, round((s.entryBoardArea * (mm.paperDensity + mm.starchDensity)) / 10000000000,0) as new_weigth_entry #, s.exitBoardArea
            , s.exitBoardWeight, round((s.exitBoardArea * (mm.paperDensity + mm.starchDensity)) / 10000000000,0) as new_weigth_exit
            FROM $MAN_DB._order o
            INNER JOIN $MAN_DB.job jb ON jb._order = o.objid AND jb.retired = 0
            INNER JOIN $PCS_DB.step s ON s.orderNumber = o.orderNumber AND s.jobId = jb.objid AND s.retired = 0
            INNER JOIN $PCS_DB.lineupentry l ON l.step = s.objid
            INNER JOIN $MAN_DB.machine m ON m.objid = l.pcsMachine 
            INNER JOIN $CSC_DB.corrugatororder co ON co.jobId = jb.objid and co.retired = 0 
            INNER JOIN $MAN_DB.materialmaster mm ON mm.objid = co.orderedBoardMasterId
            WHERE round((s.exitBoardArea * (mm.paperDensity + mm.starchDensity)) / 10000000000,0) <> COALESCE(s.exitBoardWeight,0) 
            AND s.stepNumber = 1 AND co.orderStatus NOT IN('BOARD_PRODUCED')
            -- AND o.orderNumber = '7178129030'
            ORDER BY o.orderNumber, jb.jobNumber, s.stepNumber;") || weightcorrugator="${CYAN}NoErrorsFound${NC}"
            echo -e "${RED}ObjId\tJobNumber\tStatus\tBoard\tOrgBoardEntry\tOrgBoardEntry\tOrgBoardExit\tOrgBoardExit${NC}" | expand -t7,20,30
            echo "$weightcorrugator" > $PROCESSID_weightcorrugator.tm
            cat $PROCESSID_weightcorrugator.tm
        fi
        log_message "INFO" "${GREEN}Completed verifying CSC with incorrect weight(s) in the $CSC_DB, $MAN_DB & $PCS_DB dB${NC}"

        log_message "INFO" "${YELLOW}Verifying CSC with differencies in weight to shipping in the $CSC_DB, $MAN_DB & $PCS_DB dB${NC}"
        if [ -z "$PSC_DB" ];then
            local weightconvertingcheck
            weightconvertingcheck=$(execute_mysql_query "SELECT count(*)
            FROM (SELECT s.orderNumber, s.jobNumber, s.stepNumber, c.orderStatus, s.progressStatus , l.pcsMachine, p.machineId, m.machineNumber, s.entryBoardArea, s.exitBoardArea, s.entryBoardWeight, s.exitBoardWeight 
            FROM $PCS_DB.step s
            JOIN $PCS_DB.lineupentry l ON l.step = s.objid
            JOIN $PCS_DB.pcsmachine p ON p.objid = l.pcsMachine
            JOIN $MAN_DB.machine m ON m.objid = p.machineId
            JOIN $MAN_DB.job j ON j.objid = s.jobId
            JOIN $CSC_DB.corrugatororder c ON c.jobId = j.objid 
            WHERE s.retired = 0 
            AND c.orderStatus IN ('AVAILABLE_FOR_SCHEDULING')
            AND s.progressStatus <> 'COMPLETED') AS conv_step
            JOIN (SELECT s.orderNumber, s.jobNumber, s.stepNumber, c.orderStatus, s.progressStatus, l.pcsMachine, p.machineId, m.machineNumber, s.entryBoardArea, s.exitBoardArea
            , s.entryBoardWeight, s.exitBoardWeight 
            FROM $PCS_DB.step s
            JOIN $PCS_DB.lineupentry l ON l.step = s.objid
            JOIN $PCS_DB.pcsmachine p ON p.objid = l.pcsMachine
            JOIN $MAN_DB.machine m ON m.objid = p.machineId
            JOIN $MAN_DB.job j ON j.objid = s.jobId
            JOIN $CSC_DB.corrugatororder c ON c.jobId = j.objid 
            WHERE s.retired = 0 
            AND c.orderStatus IN ('AVAILABLE_FOR_SCHEDULING') 
            AND s.progressStatus <> 'COMPLETED') AS steps ON conv_step.orderNumber = steps.orderNumber
            WHERE conv_step.exitBoardWeight <> steps.exitBoardWeight AND conv_step.exitBoardWeight <= steps.exitBoardWeight;") || weightconvertingcheck="${CYAN}NoErrorsFound${NC}"
            if [[ $DEBUG == "N" ]];then
                log_message "INFO" "${CYAN}Total records with differencies weight(s) in the $CSC_DB, $MAN_DB & $PCS_DB dB${NC}"
                log_message "INFO" "${CYAN}$weightconvertingcheck To see all run DEBUG mode${NC}"
            fi

            if [[ $weightconvertingcheck -ne 0 && $DEBUG == "Y" ]];then
                local weightconverting
                weightconverting=$(execute_mysql_query "SELECT DISTINCT steps.orderNumber, steps.jobNumber series, steps.machineNumber ,steps.orderStatus, steps.progressStatus
                , conv_step.exitBoardWeight exitBoardWeight_Conv, steps.exitBoardWeight exitBoardWeight_Exp
                FROM (SELECT s.orderNumber, s.jobNumber, s.stepNumber, c.orderStatus, s.progressStatus , l.pcsMachine, p.machineId, m.machineNumber, s.entryBoardArea, s.exitBoardArea
                , s.entryBoardWeight, s.exitBoardWeight 
                FROM $PCS_DB.step s
                JOIN $PCS_DB.lineupentry l ON l.step = s.objid
                JOIN $PCS_DB.pcsmachine p ON p.objid = l.pcsMachine
                JOIN $MAN_DB.machine m ON m.objid = p.machineId
                JOIN $MAN_DB.job j ON j.objid = s.jobId
                JOIN $CSC_DB.corrugatororder c ON c.jobId = j.objid 
                WHERE s.retired = 0 
                AND c.orderStatus IN ('AVAILABLE_FOR_SCHEDULING')
                AND s.progressStatus <> 'COMPLETED') AS conv_step
                JOIN (SELECT s.orderNumber, s.jobNumber, s.stepNumber, c.orderStatus, s.progressStatus, l.pcsMachine, p.machineId, m.machineNumber, s.entryBoardArea, s.exitBoardArea, s.entryBoardWeight, s.exitBoardWeight 
                FROM $PCS_DB.step s
                JOIN $PCS_DB.lineupentry l ON l.step = s.objid
                JOIN $PCS_DB.pcsmachine p ON p.objid = l.pcsMachine
                JOIN $MAN_DB.machine m ON m.objid = p.machineId
                JOIN $MAN_DB.job j ON j.objid = s.jobId
                JOIN $CSC_DB.corrugatororder c ON c.jobId = j.objid 
                WHERE s.retired = 0 
                AND c.orderStatus IN ('AVAILABLE_FOR_SCHEDULING') 
                AND s.progressStatus <> 'COMPLETED') AS steps ON conv_step.orderNumber = steps.orderNumber
                WHERE conv_step.exitBoardWeight <> steps.exitBoardWeight AND conv_step.exitBoardWeight <= steps.exitBoardWeight;") || weightconverting="${CYAN}NoErrorsFound${NC}"
                echo -e "${RED}ObjId\tJobNumber\tStatus\tBoard\tOrgBoardEntry\tOrgBoardEntry\tOrgBoardExit\tOrgBoardExit${NC}" | expand -t7,20,30
                echo "$weightconverting" > $PROCESSID_weightconverting.tm
                cat $PROCESSID_weightconverting.tm
            fi
        fi
        log_message "INFO" "${GREEN}Completed verifying CSC with differencies in weight to shipping in the $CSC_DB, $MAN_DB & $PCS_DB dB${NC}"

        log_message "INFO" "${GREEN}CSC Order verification completed${NC}"
    fi
}

#Look up step/job/order detail for a PCS jobid found in the bad data log
get_pcs_jobid_detail() {
    local jobid="$1"
    local detail
    log_message "INFO" "${GREEN}OrderID: ${CYAN}$order_id\t${GREEN}JobNumber: ${CYAN}$order_num\t${GREEN}Spec: ${CYAN}$spec\t${GREEN}JobID: ${CYAN}$job_id${NC}"
    log_message "INFO" "${YELLOW}Checking JobId: ${CYAN}$job_id${NC}"
    detail=$(execute_mysql_query "SELECT s.objid, s.orderNumber, j.dueTime, s.stepNumber, s.progressStatus, s.retired, alt.runDuration, alt.runDurationSource
    , s.stepAlternativePcsMachineIds, s.operationIds, m.machineNumber, s.operationSource, j.progressStatus
    , CASE
        WHEN j.jobStatus = 7 THEN 'Fully Delivered'
        WHEN j.jobStatus IN (18, 19, 20, 21) THEN 'Closed or Cancelled'
        WHEN j.jobStatus IN (3, 4, 10) THEN 'Active, Review Required'
        ELSE CONCAT('Unknown Status: ', j.jobStatus)
    END AS jobStatusName
    FROM $PCS_DB.step s
    LEFT JOIN $PCS_DB.stepalternativepcsmachine alt
        ON s.stepAlternativePcsMachineIds = alt.objid
    LEFT JOIN $PCS_DB.pcsmachine pm
        ON pm.objid = alt.pcsMachine
    LEFT JOIN $MAN_DB.machine m
        ON m.objid = pm.objid
    LEFT JOIN $MAN_DB.job j
        ON j.objid = s.jobId
    WHERE s.orderNumber IN (SELECT orderNumber
                                    FROM $MAN_DB._order
                                    WHERE objid IN (SELECT _order
                                                            FROM $MAN_DB.job
                                                            WHERE objid = '$jobid'
                                    ))
    ORDER BY s.retired desc;") || detail="${CYAN}NoErrorsFound${NC}"
    local header_line="ObjId\tOrderNumber\tDueDate\tStepNumber\tProgressStatus\tRetired\tRunDuration\tRunDurationSource\tAltPcsMachineIds\tOperationIds\tMachineNumber\tOperationSource\tJobProgressStatus\tJobStatusName"
    echo -e "${RED}${header_line}${NC}" | expand -t7,20,30
    echo -e "${header_line}" | expand -t7,20,30 >> "$LOG_FILE"
    echo "$detail" > "$PROCESSID"_logcheckpathjobid_"$job_id".tm
    cat "$PROCESSID"_logcheckpathjobid_"$job_id".tm | tee -a "$LOG_FILE"
}

#check for bad data in PCS logs
pcs_bad_data_log_check() {
    if [ -z "$PCS_DB" ];then
        log_message "INFO" "${CYAN}PCS log file is not available or unreadable${NC}"
        return
    else
        log_message "INFO" "${GREEN}Starting PCS log check tasks${NC}"

        local logcheckpathfilecheck
        logcheckpathfilecheck=$(grep -i "Bad Data" "$VUE_LOG_PATH/pcs.log.txt" | head -1) || logcheckpathfilecheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}JobIds with bad data in $VUE_LOG_PATH/pcs.log.txt ${NC}"
            if [[ -n "$logcheckpathfilecheck" ]];then
                log_message "INFO" "${RED}$logcheckpathfilecheck To see all run DEBUG mode${NC}"
            fi
        fi
        if [[ -n "$logcheckpathfilecheck" && $DEBUG == "Y" ]];then
            local logcheckpathfilecheckjobnumber
            # Pull the jobids out from between the [ ] in the log line and load them into an array
            logcheckpathfilecheckjobnumber=$(echo "$logcheckpathfilecheck" | grep -oP '(?<=\[)[^\]]*(?=\])')
            IFS=', ' read -r -a logcheckpathjobidarray <<< "$logcheckpathfilecheckjobnumber"

            log_message "INFO" "${CYAN}Found ${#logcheckpathjobidarray[@]} JobId(s) with bad data in $VUE_LOG_PATH/pcs.log.txt${NC}"

            for logcheckpathjobid in "${logcheckpathjobidarray[@]}"; do
                [[ -z "$logcheckpathjobid" ]] && continue
                JOBID="$logcheckpathjobid"
                read -r order_id order_num job_id < <(verify_pcs_order "$ORDERID" "$ORDERNUMBER" "$JOBID")
                get_pcs_jobid_detail "$logcheckpathjobid"
                display_step_details "$logcheckpathjobid"
                recommend_job_fixes "$logcheckpathjobid" "$order_num"
            done
        fi
    fi
}

#Checking the health of PCS Tables
health_check_pcs_tables() {
    if [ -z "$PCS_DB" ];then
        log_message "INFO" "${CYAN}PCS kwsql file is unreadable${NC}"
        return
    else
        log_message "INFO" "${YELLOW}Starting PCS shadow tables verification tasks${NC}"

        # Check for null finish_datetime in FACTRY table
        local factryfinishednullcheck
        factryfinishednullcheck=$(execute_mysql_query "SELECT IFNULL(COUNT(*), 0) FROM $PCS_DB.FACTRY WHERE finish_datetime = '1965-01-01 00:00:00';") || factryfinishednullcheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}Total records with factry finished datetime that are null $PCS_DB dB${NC}"
            if [[ "$factryfinishednullcheck" -ne 0 ]];then
                log_message "INFO" "${RED}$factryfinishednullcheck To see all run DEBUG mode${NC}"
            fi
        fi
        if [[ "$factryfinishednullcheck" -ne 0 && $DEBUG == "Y" ]];then
            local factryfinishednullcheckjobnumber
            factryfinishednullcheckjobnumber=$(execute_mysql_query "SELECT job_number, 'UPDATE $PCS_DB.FACTRY SET finish_datetime = ''' start_datetime ''' WHERE job_number = ''' job_number  ''' ' FROM $PCS_DB.FACTRY WHERE finish_datetime = '1965-01-01 00:00:00';") || factryfinishednullcheckjobnumber=0"${GREEN}NoErrorsFound${NC}"
            echo -e "${RED}Jobs with NULL Finished Date in $PCS_DB.FACTRY table${NC}" #| expand -t10
            # Extract the data and the rest of the string
            echo "$factryfinishednullcheckjobnumber" > "$PROCESSID".tm
            cat "$PROCESSID".tm
        fi

        # Check for null feedbackStatus and finishTime in feedback table
        local feedbackstatusfinishednullcheck
        feedbackstatusfinishednullcheck=$(execute_mysql_query "SELECT IFNULL(COUNT(*), 0) FROM $PCS_DB.feedback 
                                                                WHERE feedbackStatus IS NULL AND finishTime IS NULL;") || feedbackstatusfinishednullcheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}Total records with feedback finished datetime that are null $PCS_DB dB${NC}"
            if [[ "$feedbackstatusfinishednullcheck" -ne 0 ]];then
                log_message "INFO" "${RED}$feedbackstatusfinishednullcheck To see all run DEBUG mode${NC}"
            fi
        fi
        if [[ "$feedbackstatusfinishednullcheck" -ne 0 && $DEBUG == "Y" ]];then
            local feedbackstatusfinishednullcheckjobnumber
            feedbackstatusfinishednullcheckjobnumber=$(execute_mysql_query "SELECT f.objid AS feedbackId, f.lineupentry AS lineupEntryId, le.step AS stepId, s.orderNumber
                                                                            FROM $PCS_DB.feedback f
                                                                            LEFT JOIN $PCS_DB.lineupentry le ON le.objid = f.lineupentry
                                                                            LEFT JOIN $PCS_DB.step s ON s.objid = le.step
                                                                            WHERE feedbackStatus IS NULL AND finishTime IS NULL
                                                                            ORDER BY s.orderNumber, s.jobNumber, s.stepNumber, f.objid;") || feedbackstatusfinishednullcheckjobnumber=0"${GREEN}NoErrorsFound${NC}"
            echo -e "${RED}Jobs with NULL Status and Finished Date in $PCS_DB.feedback table${NC}" #| expand -t10
            echo -e "${RED}feedbackId\tlineupEntryId\tstepId\torderNumber${NC}" | expand -t10,20,30,40,50
            echo "$feedbackstatusfinishednullcheckjobnumber" > "$PROCESSID".tm
            cat "$PROCESSID".tm
        fi

        local feedbackeffectivenullcheck
        feedbackeffectivenullcheck=$(execute_mysql_query "SELECT IFNULL(COUNT(*), 0) FROM $PCS_DB.feedback 
                                                                WHERE effectiveStartTime > effectiveFinishTime AND effectiveFinishTime IS NOT NULL;") || feedbackeffectivenullcheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}Total records with effective start time after finish time in $PCS_DB.feedback table${NC}"
            if [[ "$feedbackeffectivenullcheck" -ne 0 ]];then
                log_message "INFO" "${RED}$feedbackeffectivenullcheck To see all run DEBUG mode${NC}"
            fi
        fi
        if [[ "$feedbackeffectivenullcheck" -ne 0 && $DEBUG == "Y" ]];then
            local feedbackeffectivenullcheckjobnumber
            feedbackeffectivenullcheckjobnumber=$(execute_mysql_query "SELECT f.objid AS feedbackId, f.lineupentry AS lineupEntryId, le.step AS stepId, s.orderNumber
                                                                            FROM $PCS_DB.feedback f
                                                                            LEFT JOIN $PCS_DB.lineupentry le ON le.objid = f.lineupentry
                                                                            LEFT JOIN $PCS_DB.step s ON s.objid = le.step
                                                                            WHERE effectiveStartTime > effectiveFinishTime AND effectiveFinishTime IS NOT NULL
                                                                            ORDER BY s.orderNumber, s.jobNumber, s.stepNumber, f.objid;") || feedbackeffectivenullcheckjobnumber=0"${GREEN}NoErrorsFound${NC}"
            echo -e "${RED}Jobs with effective start time after finish time in $PCS_DB.feedback table${NC}" #| expand -t10
            echo -e "${RED}feedbackId\tlineupEntryId\tstepId\torderNumber${NC}" | expand -t10,20,30,40,50
            echo "$feedbackeffectivenullcheckjobnumber" > "$PROCESSID".tm
            cat "$PROCESSID".tm
        fi

        local stepstatuscheck
        stepstatuscheck=$(execute_mysql_query "SELECT IFNULL(COUNT(*), 0) FROM $PCS_DB.feedback f
                                                LEFT JOIN $PCS_DB.lineupentry le ON le.objid = f.lineupentry
                                                LEFT JOIN $PCS_DB.step s ON s.objid = le.step
                                                WHERE retired = 1 AND s.progressStatus = 'NOT_SCHEDULED';") || stepstatuscheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ "$DEBUG" == "N" ]];then
            log_message "INFO" "${CYAN}Total records with step status not scheduled but retired in $PCS_DB.feedback table${NC}"
            if [[ "$stepstatuscheck" -ne 0 ]];then
                log_message "INFO" "${RED}$stepstatuscheck To see all run DEBUG mode${NC}"
            fi
        fi
        if [[ "$stepstatuscheck" -ne 0 && "$DEBUG" == "Y" ]];then
            local stepstatuscheckjobnumber
            stepstatuscheckjobnumber=$(execute_mysql_query "SELECT f.objid AS feedbackId, f.lineupentry AS lineupEntryId, le.step AS stepId, s.orderNumber
                                                                            FROM $PCS_DB.feedback f
                                                                            LEFT JOIN $PCS_DB.lineupentry le ON le.objid = f.lineupentry
                                                                            LEFT JOIN $PCS_DB.step s ON s.objid = le.step
                                                                            WHERE retired = 1 AND s.progressStatus = 'NOT_SCHEDULED'
                                                                            ORDER BY s.orderNumber, s.jobNumber, s.stepNumber, f.objid;") || stepstatuscheckjobnumber=0"${GREEN}NoErrorsFound${NC}"
            echo -e "${RED}Jobs with step status not scheduled but retired in $PCS_DB.feedback table${NC}" #| expand -t10
            echo -e "${RED}feedbackId\tlineupEntryId\tstepId\torderNumber${NC}" | expand -t10,20,30,40,50
            echo "$stepstatuscheckjobnumber" > "$PROCESSID".tm
            cat "$PROCESSID".tm
        fi

        local lineupstatuscheck
        lineupstatuscheck=$(execute_mysql_query "SELECT IFNULL(COUNT(*), 0) FROM $PCS_DB.feedback f
                                                LEFT JOIN $PCS_DB.lineupentry le ON le.objid = f.lineupentry
                                                LEFT JOIN $PCS_DB.step s ON s.objid = le.step
                                                WHERE retired = 1 AND le.progressStatus = 'NOT_SCHEDULED';") || lineupstatuscheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ "$DEBUG" == "N" ]];then
            log_message "INFO" "${CYAN}Total records with lineup status not scheduled but retired in $PCS_DB.feedback table${NC}"
            if [[ "$lineupstatuscheck" -ne 0 ]];then
                log_message "INFO" "${RED}$lineupstatuscheck To see all run DEBUG mode${NC}"
            fi
        fi
        if [[ "$lineupstatuscheck" -ne 0 && "$DEBUG" == "Y" ]];then
            local lineupstatuscheckjobnumber
            lineupstatuscheckjobnumber=$(execute_mysql_query "SELECT f.objid AS feedbackId, f.lineupentry AS lineupEntryId, le.step AS stepId, s.orderNumber
                                                                            FROM $PCS_DB.feedback f
                                                                            LEFT JOIN $PCS_DB.lineupentry le ON le.objid = f.lineupentry
                                                                            LEFT JOIN $PCS_DB.step s ON s.objid = le.step
                                                                            WHERE retired = 1 AND le.progressStatus = 'NOT_SCHEDULED'
                                                                            ORDER BY le.orderNumber, s.jobNumber, s.stepNumber, f.objid;") || lineupstatuscheckjobnumber=0"${GREEN}NoErrorsFound${NC}"
            echo -e "${RED}Jobs with lineup status not scheduled but retired in $PCS_DB.feedback table${NC}" #| expand -t10
            echo -e "${RED}feedbackId\tlineupEntryId\tstepId\torderNumber${NC}" | expand -t10,20,30,40,50
            echo "$lineupstatuscheckjobnumber" > "$PROCESSID".tm
            cat "$PROCESSID".tm
        fi

        # Check for null stepAlternativePcsMachineIds in step table
        local stepAlternatenullcheck
        stepAlternatenullcheck=$(execute_mysql_query "select IFNULL(COUNT(*),0)
                                                        FROM $PCS_DB.step WHERE retired = 0
                                                        AND (stepAlternativePcsMachineIds IS NULL OR stepAlternativePcsMachineIds = '');") || stepAlternatenullcheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ "$DEBUG" == "N" ]];then
            log_message "INFO" "${CYAN}Total records with stepAlternativePcsMachineIds that are null $PCS_DB dB${NC}"
            if [[ "$stepAlternatenullcheck" -ne 0 ]];then
                log_message "INFO" "${RED}$stepAlternatenullcheck To see all run DEBUG mode${NC}"
            fi
        fi
        if [[ "$stepAlternatenullcheck" -ne 0 && "$DEBUG" == "Y" ]];then
            local stepAlternatenullcheckjobnumber
            stepAlternatenullcheckjobnumber=$(execute_mysql_query "select objid, orderNumber, jobNumber, stepNumber, progressStatus, currentStep,
                                                                    stepAlternativePcsMachineIds, operationIds,retired
                                                                    FROM $PCS_DB.step WHERE retired = 0
                                                                    AND (stepAlternativePcsMachineIds IS NULL OR stepAlternativePcsMachineIds = '')
                                                                    ORDER BY orderNumber, jobNumber, stepNumber;") || stepAlternatenullcheckjobnumber=0"${GREEN}NoErrorsFound${NC}"
            echo -e "${RED}ADO 1064904 Jobs stepAlternativePcsMachineIds in $PCS_DB.step table${NC}" #| expand -t10
            # Extract the data and the rest of the string
            echo "$stepAlternatenullcheckjobnumber" > "$PROCESSID".tm
            cat "$PROCESSID".tm
        fi

        log_message "INFO" "${GREEN}PCS tables verification completed${NC}"
    fi
}

# Function to check the heatlh of PCS
health_check_pcs_order() {
    if [ -z "$PCS_DB" ];then
        log_message "INFO" "${CYAN}PSC Is not Installed${NC}"
        return
    else
        log_message "INFO" "${GREEN}Starting PCS verification tasks${NC}"

        log_message "INFO" "${YELLOW}Verifying PCS order materialfeedback that do not have jobnumber in the $PCS_DB dB${NC}"
        local nullmaterialfeedbackcheck
        nullmaterialfeedbackcheck=$(execute_mysql_query "SELECT count(*) FROM $PCS_DB.materialfeedback WHERE feedback IN (SELECT objid FROM $PCS_DB.feedback WHERE lineupentry IN
             (SELECT objId FROM $PCS_DB.lineupentry WHERE step IN (select objId FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order))));") || nullmaterialfeedbackcheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}Total records with materialfeedback that do not have jobnumber $PCS_DB dB${NC}"
            log_message "INFO" "${CYAN}$nullmaterialfeedbackcheck To see all run DEBUG mode${NC}"
        fi

        if [[ $nullmaterialfeedbackcheck -ne 0 && $DEBUG == "Y" ]];then
            local nullmaterialfeedbackjob
            nullmaterialfeedbackjob=$nullmaterialfeedbackcheck
            echo -e "${RED}StepCount_Orphaned${NC}" | expand -t10
            # Extract the number and the rest of the string
            number=$(echo "$nullmaterialfeedbackjob" | grep -o '^[0-9]*')
            # Use printf to pad the number to 20 spaces after the first expand -t padding
            printf "%-20s%s\n" "$number" "$rest" > $PROCESSID_$nullmaterialfeedbackjob.tm
            cat $PROCESSID_$nullmaterialfeedbackjob.tm
        fi

        log_message "INFO" "${YELLOW}Verifying PCS order feedback that do not have jobnumber in the $PCS_DB dB${NC}"
        local nullfeedbackcheck
        nullfeedbackcheck=$(execute_mysql_query "SELECT COUNT(*) FROM $PCS_DB.feedback WHERE lineupentry IN (SELECT objId FROM $PCS_DB.lineupentry WHERE step IN 
             (select objId FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order)));") || nullfeedbackcheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}Total records with feedback that do not have jobnumber $PCS_DB dB${NC}"
            log_message "INFO" "${CYAN}$nullfeedbackcheck To see all run DEBUG mode${NC}"
        fi

        if [[ $nullfeedbackcheck -ne 0 && $DEBUG == "Y" ]];then
            local feedbacknull
            feedbacknull=$nullfeedbackcheck
            echo -e "${RED}FeedBack_Orphaned${NC}" | expand -t10
            # Extract the number and the rest of the string
            number=$(echo "$feedbacknull" | grep -o '^[0-9]*')
            # Use printf to pad the number to 20 spaces after the first expand -t padding
            printf "%-20s%s\n" "$number" "$rest" > $PROCESSID_$feedbacknull.tm
            cat $PROCESSID_$feedbacknull.tm
        fi
        log_message "INFO" "${GREEN}Completed verifying PCS order feedback that do not have jobnumber in the dB${NC}"

        log_message "INFO" "${YELLOW}Verifying PCS order lineupentry that do not have jobnumber in the $PCS_DB dB${NC}"
        local lineupentrynullcheck
        lineupentrynullcheck=$(execute_mysql_query "SELECT COUNT(*) FROM $PCS_DB.lineupentry WHERE step IN (select objId FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order));") || lineupentrynull=0"${GREEN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}Total records with lineupentry that do not have jobnumber $PCS_DB dB${NC}"
            log_message "INFO" "${CYAN}$lineupentrynullcheck To see all run DEBUG mode${NC}"
        fi

        if [[ $lineupentrynullcheck -ne 0 && $DEBUG == "Y" ]];then
            local lineupentrynull
            lineupentrynull=$lineupentrynullcheck
            echo -e "${RED}LineupEntry_Orphaned${NC}" | expand -t10
            # Extract the number and the rest of the string
            number=$(echo "$lineupentrynull" | grep -o '^[0-9]*')
            # Use printf to pad the number to 20 spaces after the first expand -t padding
            printf "%-20s%s\n" "$number" "$rest" > $PROCESSID_lineupentrynull.tm
            cat $PROCESSID_lineupentrynull.tm
        fi
        log_message "INFO" "${GREEN}Completed verifying PCS order lineupentry that do not have jobnumber in the $PCS_DB dB${NC}"

        log_message "INFO" "${YELLOW}Verifying PCS order matertialstep that do not have jobnumber in the $PCS_DB dB${NC}"
        local matertialstepnullcheck
        matertialstepnullcheck=$(execute_mysql_query "SELECT count(*) FROM $PCS_DB.materialatstep WHERE step IN (SELECT objid FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order));") || lineupentrynull=0"${GREEN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}Total records with matertialstep that do not have jobnumber $PCS_DB dB${NC}"
            log_message "INFO" "${CYAN}$matertialstepnullcheck To see all run DEBUG mode${NC}"
        fi

        if [[ $matertialstepnullcheck -ne 0 && DEGUB == "Y" ]];then
            local matertialstepnull
            matertialstepnull=$matertialstepnullcheck
            echo -e "${RED}MatertialStep_Orphaned${NC}" | expand -t10
            # Extract the number and the rest of the string
            number=$(echo "$matertialstepnull" | grep -o '^[0-9]*')
            # Use printf to pad the number to 20 spaces after the first expand -t padding
            printf "%-20s%s\n" "$number" "$rest" > $PROCESSID_matertialstepnull.tm
            cat $PROCESSID_matertialstepnull.tm
        fi
        log_message "INFO" "${GREEN}Completed verifying PCS order matertialstep that do not have jobnumber in the $PCS_DB dB${NC}"

        log_message "INFO" "${YELLOW}Verifying PCS order steps that do not have jobnumber in the $PCS_DB dB${NC}"
        local nullstepheck
        nullstepheck=$(execute_mysql_query "SELECT COUNT(*) FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order);") || nulljobcheck=0"${GREEN}NoErrorsFound${NC}"
        if [[ $DEBUG == "N" ]];then
            log_message "INFO" "${CYAN}Total records with steps that do not have jobnumber $PCS_DB dB${NC}"
            log_message "INFO" "${CYAN}$nullstepheck To see all run DEBUG mode${NC}"
        fi

        if [[ $nullstepheck -ne 0 && DEBUG == "Y" ]];then
            local nulljob
            nulljob=$nullstepheck
            echo -e "${RED}StepCount_Orphaned${NC}" | expand -t10
            # Extract the number and the rest of the string
            number=$(echo "$nulljob" | grep -o '^[0-9]*')
            # Use printf to pad the number to 20 spaces after the first expand -t padding
            printf "%-20s%s\n" "$number" "$rest" > $PROCESSID_nulljob.tm
            cat $PROCESSID_nulljob.tm
        fi
        log_message "INFO" "${GREEN}Completed verifying PCS order steps that do not have jobnumber in the $PCS_DB dB${NC}"

        if [[ $nullmaterialfeedbackcheck -ne 0 || $nullfeedbackcheck -ne 0 || $lineupentrynullcheck -ne 0 || $matertialstepnullcheck -ne 0 || $nullstepheck -ne 0 ]];then
            log_message "WARN" "${YELLOW}##################################################################################################${NC}"
            log_message "WARN" "${YELLOW}Based on the prior searches the following should be looked at.${NC}"
            log_message "WARN" "${YELLOW}These should be fixed as they are orfaned records that can cause the PCS scheduler to stop working${NC}"
            log_message "WARN" "${YELLOW}If you are deleting one by one you will need to get the ojbId from the log file${NC}"
            log_message "WARN" "${YELLOW}##To fix the errors NOTE: replace the SELECT with a DELETE ##${NC}"
            log_message "WARN" "${CYAN}   SELECT * FROM $PCS_DB.materialfeedback WHERE feedback IN
                                    (SELECT objid FROM $PCS_DB.feedback WHERE lineupentry IN (SELECT objId FROM $PCS_DB.lineupentry WHERE step IN
                                    (select objId FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order))));
                                SELECT * FROM $PCS_DB.feedback WHERE lineupentry IN (SELECT objId FROM $PCS_DB.lineupentry WHERE step IN
                                    (select objId FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order)));
                                SELECT * FROM $PCS_DB.lineupentry WHERE step IN (SELECT objId FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order));
                                SELECT * FROM $PCS_DB.materialatstep WHERE step IN (SELECT objid FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order));
                                SELECT * FROM $PCS_DB.step WHERE ordernumber NOT IN (SELECT orderNumber FROM $MAN_DB._order);${NC}"
            log_message "WARN" "${YELLOW}##################################################################################################${NC}"
        fi

        if [ -n "$CSC_DB" ];then
            log_message "INFO" "${YELLOW}Verifying PCS with differencies in weight to shipping in the $MAN_DB & $PCS_DB dB${NC}"
            local weightconvertingcheck
            weightconvertingcheck=$(execute_mysql_query "SELECT DISTINCT count(*)
            FROM (SELECT s.orderNumber, s.jobNumber, s.stepNumber, s.progressStatus , l.pcsMachine, p.machineId, m.machineNumber, s.entryBoardArea, s.exitBoardArea, s.entryBoardWeight, s.exitBoardWeight 
            FROM $PCS_DB.step s
            JOIN $PCS_DB.lineupentry l ON l.step = s.objid
            JOIN $PCS_DB.pcsmachine p ON p.objid = l.pcsMachine
            JOIN $MAN_DB.machine m ON m.objid = p.machineId
            JOIN $MAN_DB.job j ON j.objid = s.jobId
            WHERE s.retired = 0 
            AND s.progressStatus <> 'COMPLETED') AS conv_step
            JOIN (SELECT s.orderNumber, s.jobNumber, s.stepNumber, s.progressStatus, l.pcsMachine, p.machineId, m.machineNumber, s.entryBoardArea, s.exitBoardArea, s.entryBoardWeight, s.exitBoardWeight 
            FROM $PCS_DB.step s
            JOIN $PCS_DB.lineupentry l ON l.step = s.objid
            JOIN $PCS_DB.pcsmachine p ON p.objid = l.pcsMachine
            JOIN $MAN_DB.machine m ON m.objid = p.machineId
            JOIN $MAN_DB.job j ON j.objid = s.jobId
            WHERE s.retired = 0 
            AND s.progressStatus <> 'COMPLETED') AS steps ON conv_step.orderNumber = steps.orderNumber
            WHERE conv_step.exitBoardWeight <> steps.exitBoardWeight AND conv_step.exitBoardWeight <= steps.exitBoardWeight;") || areacorrugator="${CYAN}NoErrorsFound${NC}"
            if [[ $DEBUG == "N" ]];then
                log_message "INFO" "${CYAN}Total records with differencies in weight to shipping in the $MAN_DB & $PCS_DB dB${NC}"
                log_message "INFO" "${CYAN}$weightconvertingcheck To see all run DEBUG mode${NC}"
            fi

            if [[ $weightconvertingcheck -ne 0 && DEGUB == "Y" ]];then
                local weightconverting
                weightconverting=$(execute_mysql_query "SELECT DISTINCT steps.orderNumber, steps.jobNumber series, steps.machineNumber, steps.progressStatus, conv_step.exitBoardWeight exitBoardWeight_Conv, steps.exitBoardWeight exitBoardWeight_Exp
                FROM (SELECT s.orderNumber, s.jobNumber, s.stepNumber, s.progressStatus , l.pcsMachine, p.machineId, m.machineNumber, s.entryBoardArea, s.exitBoardArea, s.entryBoardWeight, s.exitBoardWeight 
                FROM $PCS_DB.step s
                JOIN $PCS_DB.lineupentry l ON l.step = s.objid
                JOIN $PCS_DB.pcsmachine p ON p.objid = l.pcsMachine
                JOIN $MAN_DB.machine m ON m.objid = p.machineId
                JOIN $MAN_DB.job j ON j.objid = s.jobId
                WHERE s.retired = 0 
                AND s.progressStatus <> 'COMPLETED') AS conv_step
                JOIN (SELECT s.orderNumber, s.jobNumber, s.stepNumber, s.progressStatus, l.pcsMachine, p.machineId, m.machineNumber, s.entryBoardArea, s.exitBoardArea, s.entryBoardWeight, s.exitBoardWeight 
                FROM $PCS_DB.step s
                JOIN $PCS_DB.lineupentry l ON l.step = s.objid
                JOIN $PCS_DB.pcsmachine p ON p.objid = l.pcsMachine
                JOIN $MAN_DB.machine m ON m.objid = p.machineId
                JOIN $MAN_DB.job j ON j.objid = s.jobId
                WHERE s.retired = 0 
                AND s.progressStatus <> 'COMPLETED') AS steps ON conv_step.orderNumber = steps.orderNumber
                WHERE conv_step.exitBoardWeight <> steps.exitBoardWeight AND conv_step.exitBoardWeight <= steps.exitBoardWeight;") || areacorrugator="${CYAN}NoErrorsFound${NC}"
                echo -e "${RED}ObjId\tJobNumber\tStatus\tBoard\tOrgBoardEntry\tOrgBoardEntry\tOrgBoardExit\tOrgBoardExit${NC}" | expand -t7,20,30
                echo "$weightconverting" > $PROCESSID_weightconverting.tm
                cat $PROCESSID_weightconverting.tm
            fi
            log_message "INFO" "${GREEN}Completed verifying PSC with differencies in weight to shipping in the $CSC_DB, $MAN_DB & $PCS_DB dB${NC}"
        fi

        log_message "INFO" "${GREEN}PSC Order verification completed${NC}\n"

    fi
}

# Function to Verify RSS
health_check_rss() {
    if [ -n "$CLASSIC" ];then
    local rssexists
    rssexists=$(execute_mysql_query "SELECT COUNT(*) FROM master WHERE tname='RSSSTK' AND available='Y';" "$CLASSIC") || rssexists="${CYAN}NoErrorsFound${NC}"
        if [ -z "$rssexists" ];then
            log_message "INFO" "${CYAN}RSS Is not Installed${NC}"
            return
        else
            log_message "INFO" "${CYAN}RSS Is Installed${NC}"
        fi
    fi
}

# Function to Verify ULT
health_check_ult() {
    if [ -n "$CLASSIC" ];then
        local ultexists
        ultexists=$(execute_mysql_query "SELECT COUNT(*) FROM master WHERE tname='ULOADC' AND available='Y';" "$CLASSIC") || iltexists="${CYAN}NoErrorsFound${NC}"
        if [ -z "$ultexists" ];then
            log_message "INFO" "${CYAN}ULT Is not Installed${NC}"
            return
        else
            log_message "INFO" "${CYAN}ULT Is Installed${NC}"
        fi
    fi
}

# Function to check the heatlh of QMS
health_check_qms_order() {
    if [ -z "$QMS_DB" ];then
        log_message "INFO" "${CYAN}QMS Is not Installed${NC}"
        return
    else
        log_message "INFO" "${CYAN}QMS Is Installed${NC}"
    fi

    log_message "INFO" "${YELLOW}Starting QMS verification tasks\n"
    
    # log_message "INFO" "${YELLOW}Verifying CSC orders that have a NULL corrugator in the $CSC_DB dB${NC}"
    # local nullcorrugator
    # nullcorrugator=$(execute_mysql_query "select LPAD(COALESCE(corrugator,''),10,' '), count(*) from corrugatororder group by corrugator;" "$CSC_DB") || nullcorrugator="${GREEN}NoErrorsFound${NC}"
    # echo -e "${RED}Corrugator\tOrderCount${NC}" | expand -t10,22
    # echo "$nullcorrugator" > $PROCESSID_nullcorrugator.tm
    # cat $PROCESSID_nullcorrugator.tm
    # log_message "INFO" "${GREEN}Completed verifying CSC orders that have a NULL corrugator in the $CSC_DB dB${NC}"

    log_message "INFO" "${GREEN}QMS Order verification completed for $order_num${NC}\n"
}

# Function to check the heatlh of TSS
health_check_tss_order() {
    if [ -z "$TSS_DB" ];then
        log_message "INFO" "${CYAN}TSS Is not Installed${NC}"
        return
    else
        log_message "INFO" "${CYAN}TSS Is Installed${NC}"
    fi

    log_message "INFO" "${YELLOW}Starting TSS verification tasks\n"
    
    log_message "INFO" "${YELLOW}Verifying TSS orders that are not in scheduled in the $TSS_DB dB${NC}"
    local nonescheduledorders
    nonescheduledorders=$(execute_mysql_query "SELECT LPAD(COALESCE(COUNT(*),''),10,' '), 'SELECT legacyJobId, legacyJobSpec, status_code FROM deliveryjobstepseries WHERE status_code = ''NON_SHIPMENT'''
    FROM deliveryjobstepseries WHERE status_code ='NON_SHIPMENT';" "$TSS_DB") || nonescheduledorders=0
    echo -e "${RED}OrderCount\tUpdate Command Fix${NC}" | expand -t10,22
    echo "$nonescheduledorders" > $PROCESSID_nonescheduledorders.tm
    cat $PROCESSID_nonescheduledorders.tm
    log_message "INFO" "${GREEN}Completed verifying TSS orders that are not in scheduled in the $CSC_DB dB${NC}"

    log_message "INFO" "${GREEN}TSS Order verification completed for $order_num${NC}\n"
}

# Function to verify order
verify_pcs_order() {
    local ord_id="$ORDERID"
    local ord_num="$ORDERNUMBER"
    local ord_jobid="$JOBID"
    #local char_count=$(echo -n "$input" | wc -c)
    local order_id order_num job_id

    # Input is Job ID
    if [[ -n "$ord_jobid" && -z "$ord_num" && -z "$ord_id" ]]; then
        job_id="$ord_jobid"
        order_id=$(execute_mysql_query "SELECT _order FROM $MAN_DB.job WHERE objid = '$job_id';")
        order_num=$(execute_mysql_query "SELECT orderNumber FROM $MAN_DB._order WHERE objid = '$order_id';")
    fi
    # Input is Order Number
    if [[ -z "$ord_jobid" && -n "$ord_num" && -z "$ord_id" ]]; then
        order_num="$ord_num"
        order_id=$(execute_mysql_query "SELECT objid FROM $MAN_DB._order WHERE orderNumber = '$order_num';")
        job_id=$(execute_mysql_query "SELECT objid FROM $MAN_DB.job WHERE _order = '$order_id';")
    fi
    # Input is Order ID
    if [[ -z "$ord_jobid" && -z "$ord_num" && -n "$ord_id" ]]; then
        order_id="$ord_id"
        order_num=$(execute_mysql_query "SELECT orderNumber FROM $MAN_DB._order WHERE objid = '$order_id';")
        job_id=$(execute_mysql_query "SELECT objid FROM $MAN_DB.job WHERE _order = '$order_id';")
    fi
    echo -e "$order_id" "$order_num" "$job_id"

}

# Function to display order details
display_order_details() {
    local order_id="$1"
    local order_num="$2"
    local job_id="$3"

    echo -e "${YELLOW}Details of the order${NC}"
    local spec
    spec=$(execute_mysql_query "SELECT oname 
        FROM $MAN_DB._order 
        LEFT JOIN $MAN_DB.specification spec 
        ON _order.masterSpecification=spec.objid WHERE _order.objid='$order_id';")
    echo -e "${GREEN}OrderID: ${CYAN}$order_id\t${GREEN}JobNumber: ${CYAN}$order_num\t${GREEN}Spec: ${CYAN}$spec\t${GREEN}JobID: ${CYAN}$job_id${NC}"
    echo -e "${YELLOW}Objid\tStep\tProgress\tRetired\tRun_Min\tSource\tAltMach\tOps\tMachine\tOperationSource${NC}"
    local steps_data
    steps_data=$(execute_mysql_query "SELECT step.objid, stepNumber, progressStatus, step.retired, alt.runDuration, alt.runDurationSource, stepAlternativePcsMachineIds, operationIds, m.machineNumber, operationSource
        FROM $PCS_DB.step 
        LEFT JOIN $PCS_DB.stepalternativepcsmachine alt on step.stepAlternativePcsMachineIds=alt.objid 
        LEFT JOIN $PCS_DB.pcsmachine pm ON pm.objid = alt.pcsMachine
        LEFT JOIN $MAN_DB.machine m ON m.objid = pm.objid 
        WHERE jobId = '$job_id';")
    echo "$steps_data" > $PROCESSID_steps.tm
    cat $PROCESSID_steps.tm
}

# Function to display step details
display_step_details() {
    local job_id="$1"
    local num_steps
    num_steps=$(execute_mysql_query "SELECT COUNT(DISTINCT stepNumber)
        FROM $PCS_DB.step
        LEFT JOIN $PCS_DB.stepalternativepcsmachine alt
        ON step.stepAlternativePcsMachineIds=alt.objid WHERE jobId = '$job_id';" "$PCS_DB")

    local scount=1
    while [ "$scount" -le "$num_steps" ]; do
        local step_data
        step_data=$(execute_mysql_query "SELECT step.objid
            FROM $PCS_DB.step
            LEFT JOIN $PCS_DB.stepalternativepcsmachine alt
            ON step.stepAlternativePcsMachineIds=alt.objid WHERE stepNumber = $scount AND jobId = '$job_id';" "$PCS_DB")

        local step_ids=()
        mapfile -t step_ids <<< "$step_data"

        local step_objid
        for step_objid in "${step_ids[@]}"; do
            [[ -z "$step_objid" ]] && continue
            echo -e "\n${GREEN}LINEUP Entry Data for Step: ${CYAN}$scount${YELLOW} - ObjID: ${CYAN}$step_objid${NC}"

            local lineup_data
            lineup_data=$(execute_mysql_query "SELECT COALESCE(le.objid,''), RPAD(COALESCE(progressStatus,''),15,' '), LPAD(COALESCE(m.oname,''),4,' '), RPAD(COALESCE(plannedQuantityProduced,''),10,' ')
            FROM lineupentry le INNER JOIN pcsmachine pm ON le.pcsMachine=pm.objid
            INNER JOIN $MAN_DB.machine m ON pm.machineId=m.objid WHERE step = $step_objid;" "$PCS_DB")

            if [ -z "$lineup_data" ]; then
                echo -e "${RED}No LINEUP Entry Data found for StepObjectID: ${CYAN}$step_objid${NC}"
            else
                echo -e "${YELLOW}Objid\tStatus\t\tMachine\tQuantity${NC}"
                echo "$lineup_data"
            fi

            local linedata
            linedata=$(execute_mysql_query "SELECT le.objid
                FROM $PCS_DB.lineupentry le
                INNER JOIN $PCS_DB.pcsmachine pm ON le.pcsMachine=pm.objid
                INNER JOIN $MAN_DB.machine m ON pm.machineId=m.objid WHERE step = $step_objid;" "$PCS_DB")

            local lineup_ids=()
            mapfile -t lineup_ids <<< "$linedata"

            local le_objid
            for le_objid in "${lineup_ids[@]}"; do
                [[ -z "$le_objid" ]] && continue
                echo -e "${GREEN}FEEDBACK for LINE Entry ${CYAN}$le_objid${NC}"

                local feedback_data
                feedback_data=$(execute_mysql_query "SELECT RPAD(COALESCE(feedbackStatus,''),15,' '), objid, LPAD(COALESCE(FROM_UNIXTIME(startTime/1000),''),24,' '),
                LPAD(COALESCE(FROM_UNIXTIME(SetupCompletionTime/1000),''),24,' '), LPAD(COALESCE(FROM_UNIXTIME(finishtime/1000),''),24,' '),
                LPAD(COALESCE(ReportDate,''),10,' '), RPAD(COALESCE(shiftId,''),7,' '), explicitQuantityFedDuringRun, explicitQuantityProduced, derivedFeedback
                FROM feedback WHERE lineupentry = $le_objid;" "$PCS_DB")

                if [ -z "$feedback_data" ]; then
                    echo -e "\n${RED}No FEEDBACK for LINE Entry found for LineupEntryObjectId: ${CYAN}$le_objid${NC}"
                else
                    echo -e "${YELLOW}Status\tOBJID\tStart Time\tSetup Time\tFinish Time\tReport_Shift\tShftId\tQ_Fed\tQ_Prd\tDerived${NC}" | expand -t22,26,30,62,94,126,142,150,158,166
                    echo "$feedback_data"
                fi

                local derived_id
                derived_id=$(execute_mysql_query "SELECT derivedFeedback FROM $PCS_DB.feedback WHERE lineupentry = $le_objid;" "$PCS_DB")

                local derived_data
                derived_data=$(execute_mysql_query "SELECT RPAD(COALESCE('MDC Derived',''),15,' '), objid, COALESCE(FROM_UNIXTIME(detectedStartTime/1000),''),
                COALESCE(FROM_UNIXTIME(detectedSetupFinishTime/1000),''), COALESCE(FROM_UNIXTIME(detectedFinishTime/1000),''),
                '          ' ReportDate, '        ' ShiftId, detectedRunQuantityFed, detectedQuantityProduced, ' ' derivedFeedback
                FROM derivedfeedback WHERE objid = '$derived_id';" "$PCS_DB")

                if [ -z "$derived_data" ]; then
                    echo -e "\n${RED}No DIREVEDFEEDBACK for LINE Entry found for LineupEntryObjectId: ${CYAN}$le_objid${NC}"
                else
                    echo "$derived_data"
                fi
            done
        done
        scount=$((scount + 1))
    done
}

# Function to handle order actions
handle_order_action() {
    local order_num="$1"
    local step_data="$2"
    local linedata="$3"
    local action="$4"
    local runduration="$5"
    local job_id="$6"
    local step="$7"

    case "${action,,}" in
        "close")
            log_message "WARN" "${YELLOW}Order $order_num Lineupentry:$linedata Step:$step_data should be COMPLETED. Run the following to fix it:${NC}"
            log_message "WARN" "${CYAN}   UPDATE step SET progressStatus='COMPLETED' WHERE objid=$step_data;${NC}"
            log_message "WARN" "${CYAN}   UPDATE lineupentry SET progressStatus='COMPLETED' WHERE objid=$linedata;${NC}"
            ;;
        "open")
            log_message "WARN" "${YELLOW}Order $order_num Lineupentry:$linedata Step:$step_data should be NOT_SCHEDULED. Run the following to fix it:${NC}"
            log_message "WARN" "${CYAN}   UPDATE step SET progressStatus='NOT_SCHEDULED' WHERE objid=$step_data;${NC}"
            log_message "WARN" "${CYAN}   UPDATE lineupentry SET progressStatus='NOT_SCHEDULED' WHERE objid=$linedata;${NC}"
            ;;
        "run")
            local alter_data
            alter_data=$(execute_mysql_query "SELECT stepAlternativePcsMachineIds FROM step LEFT JOIN stepalternativepcsmachine alt ON step.stepAlternativePcsMachineIds=alt.objid WHERE jobId = '$job_id' AND step.stepNumber='$step';" "$PCS_DB" | grep -v "objid" | tr "," "\n")

            local alter_ids=()
            mapfile -t alter_ids <<< "$alter_data"

            local alter
            for alter in "${alter_ids[@]}"; do
                [[ -z "$alter" ]] && continue
                log_message "WARN" "${YELLOW}Order $order_num Step:$step Alternative:$alter run duration should be $runduration. Run the following to fix it:${NC}"
                log_message "WARN" "${CYAN}   UPDATE stepalternativepcsmachine SET runDuration='$runduration' WHERE objid='$alter';${NC}"
                log_message "WARN" "${CYAN}   UPDATE stepalternativepcsmachine SET runDurationSource='USER' WHERE objid='$alter';${NC}"
            done
            ;;
        *)
            log_message "ERROR" "Invalid action: $action"
            exit 1
            ;;
    esac
}

# Function to recommend the best available fix(es) for a job flagged with bad data.
# Reuses the same retired/progressStatus mismatch conditions as health_check_pcs_tables.
recommend_job_fixes() {
    local job_id="$1"
    local order_num="$2"

    # close: step & lineupentry both retired but never marked COMPLETED
    local close_candidate
    close_candidate=$(execute_mysql_query "SELECT s.objid, s.stepNumber, le.objid
        FROM $PCS_DB.step s
        INNER JOIN $PCS_DB.lineupentry le ON le.step = s.objid
        WHERE s.jobId = '$job_id' AND s.retired = 1 AND s.progressStatus = 'NOT_SCHEDULED'
        AND le.retired = 1 AND le.progressStatus = 'NOT_SCHEDULED'
        ORDER BY s.stepNumber LIMIT 1;" "$PCS_DB")
    if [[ -n "$close_candidate" ]]; then
        local step_objid step_number line_objid
        read -r step_objid step_number line_objid <<< "$close_candidate"
        handle_order_action "$order_num" "$step_objid" "$line_objid" "close" "" "$job_id" "$step_number"
    fi

    # open: lineupentry marked COMPLETED but no feedback finishTime was ever recorded
    local open_candidate
    open_candidate=$(execute_mysql_query "SELECT s.objid, s.stepNumber, le.objid
        FROM $PCS_DB.lineupentry le
        INNER JOIN $PCS_DB.step s ON s.objid = le.step
        WHERE s.jobId = '$job_id' AND le.progressStatus = 'COMPLETED'
        AND NOT EXISTS (SELECT 1 FROM $PCS_DB.feedback f WHERE f.lineupentry = le.objid AND f.finishTime IS NOT NULL)
        ORDER BY s.stepNumber LIMIT 1;" "$PCS_DB")
    if [[ -n "$open_candidate" ]]; then
        local step_objid step_number line_objid
        read -r step_objid step_number line_objid <<< "$open_candidate"
        handle_order_action "$order_num" "$step_objid" "$line_objid" "open" "" "$job_id" "$step_number"
    fi

    # run: alternative machine has no runDuration but a measured derivedfeedback duration exists
    local run_candidate
    run_candidate=$(execute_mysql_query "SELECT s.stepNumber, TIMESTAMPDIFF(MINUTE, FROM_UNIXTIME(df.detectedSetupFinishTime/1000), FROM_UNIXTIME(df.detectedFinishTime/1000))
        FROM $PCS_DB.step s
        INNER JOIN $PCS_DB.stepalternativepcsmachine alt ON alt.objid = s.stepAlternativePcsMachineIds
        INNER JOIN $PCS_DB.lineupentry le ON le.step = s.objid
        INNER JOIN $PCS_DB.feedback f ON f.lineupentry = le.objid
        INNER JOIN $PCS_DB.derivedfeedback df ON df.objid = f.derivedFeedback
        WHERE s.jobId = '$job_id' AND COALESCE(alt.runDuration,0) = 0
        AND df.detectedSetupFinishTime IS NOT NULL AND df.detectedFinishTime IS NOT NULL
        ORDER BY s.stepNumber LIMIT 1;" "$PCS_DB")
    if [[ -n "$run_candidate" ]]; then
        local step_number measured_minutes
        read -r step_number measured_minutes <<< "$run_candidate"
        if [[ "$measured_minutes" =~ ^[0-9]+$ ]] && [ "$measured_minutes" -gt 0 ]; then
            handle_order_action "$order_num" "" "" "run" "$measured_minutes" "$job_id" "$step_number"
        fi
    fi
}

# Main function
main() {
    # Rotate log
    rotate_log
    #cd $HOME
    
    # Check is base direcotry exists
    check_kiwibase
    
    # Validate any variables that MUST exist
    check_plantid "PLANTID"
    
    # Get the environment variables from the configuration file
    get_environment
    
    # Check if a newer version of this script is available
    check_for_updates

    # Check for required commands
    check_command mysql
    check_command grep
    check_command awk

    # Verify/Create folders
    create_folders    
    # Notes to the user
    notes
    # Server information
    drivespace
    # Kiwiplan Software Info
    kiwiplan
    # 
    get_systemd

    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    log_message "INFO" "${CYAN}Starting Health Check on the VUE systems${NC}"

    #Verify PCS Manually
    if [[ -n "$ORDERNUMBER" || -n "$ORDERID" || -n "$JOBID" ]];then
       
        log_message "INFO" "${YELLOW}Starting Manual PCS Steps verification${NC}"
        read -r order_id order_num job_id < <(verify_pcs_order "$ORDERID" "$ORDERNUMBER" "$JOBID")
        # Display order details
        get_pcs_jobid_detail "$job_id"
        #display_order_details "$order_id" "$order_num" "$job_id"
        # Handle step details if provided
        #display_step_details "$num_steps" "$job_id"
        # Handle actions for updates and ect.. if provided
        if [ -n "" ]; then
            local step_data
            step_data=$(head -n 1 $PROCESSID_steps.tm | cut -c1-6 | tr -d " ")
            local linedata
            linedata=$(head -n 1 $PROCESSID_lineup.tm | cut -c1-6 | tr -d " ")
            handle_order_action "$order_num" "$step_data" "$linedata" "$3" "$4" "$job_id" "$2"
        fi
        log_message "INFO" "${GREEN}PCS Order verification completed for $order_num${NC}"

       else
    
        # Verify Heatlh PCS Logs
        pcs_bad_data_log_check
        # Verify Heatlh CSC
        health_check_csc_order
        # Verify Heatlh PCS Tables
        health_check_pcs_tables
        # Verify Heatlh PCS
        health_check_pcs_order
        # Verify Health RSS
        health_check_rss
        # Verify Health ULT
        health_check_ult
        # Verify Heatlh QMS
        health_check_qms_order
        # Verify Heatlh TSS
        health_check_tss_order

    fi

    #log_message "INFO" "${YELLOW}Cleaning up my working files called $PROCESSID_*.tm${NC}"
    #rm $PROCESSID_*.tm
    #log_message "INFO" "${GREEN}Cleanup completed${NC}"
    log_message "INFO" "${GREEN}Finished Health Check on the VUE systems${NC}"

    # Email this run's log to MAILTO
    send_report_email
    log_message "INFO" "${GREEN}Emailed health check log to $MAILTO${NC}"

    return 0
}

# Trap errors
trap 'log_message "ERROR" "Script terminated unexpectedly at line $LINENO"; exit 1' ERR

# Execute main function
main "$@"
exit $?
