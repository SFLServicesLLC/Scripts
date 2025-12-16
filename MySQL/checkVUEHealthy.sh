#!/bin/bash

#===============================================================================
# Script Name: checkVUEHealthy.sh
# Description: Verify and manage VUE application errors and data intergrity
# 
# Created By: Steve Ling
# Created On: 2025-09-23
# 
# Modified By: 
# Modified On: 
# Modification Notes: 
# 
VERSION=2.1.0
# License: MIT License
# 
# Dependencies:]
# Usage:
# 
# WARNING: 
# 
# Changelog:
# - 2025-09-24: [VERSION] - [SUMMARY OF CHANGES]
# - 2025-11-09: [VERSION] - [INITIAL CREATION]
#===============================================================================

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
MAX_LOG_SIZE=$((5*1024*1024)) 			# 5MB
LOG_DIR=$(dirname "$LOG_FILE")			# Path of logging directory
PROCESSID=$(date +%Y%m%d_%k%M%S)        # Your own process ID

# Database credentials
: "${DEBUG:=N}"					                                        # Debug Mode
#: "${PLANTID:?Error: PLANTID is not supplied}"	                        # Dataset plantcode
: "${PLANTID:$PLANTID}"				                                    # Dataset plantcode
: "${MYSQL_HOST:=localhost}"		                                    # MySQL host
: "${MYSQL_USER:=$(grep "USER=" $DATA/kwsql|cut -d"=" -f2)}"			# MySQL username
: "${MYSQL_PASSWORD:=$(grep "PASSWORD=" $DATA/kwsql|cut -d"=" -f2)}"	# MySQL password
: "${ORDERNUMBER:=}"				                                    # Order Number to use
: "${ORDERID:=}"				                                        # Order ID to use
: "${JOBID:=}"					                                        # Job ID to use

# Ensure log directory exists
create_folders() {
if [ ! -d "$LOG_FOLDER" ];then
    log_message "INFO" "${YELLOW}Creating log folder $LOG_FOLDER${NC}"
    mkdir -p "$LOG_FOLDER"
else
    log_message "INFO" "${GREEN}Log folder $LOG_DIR exists${NC}"
fi
}

#Get dataset enviroment information
get_environment() {

    KIWIBASE=${KIWIBASE:-/opt/kiwi}
    PORTS=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep OFFSET|cut -d"=" -f2)
    CLASSIC=$(grep "DATA=" $DATA/kwsql|cut -d"=" -f2)
    CSC_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.CSC_DBNAME|cut -d"=" -f2)
    PCS_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.PCS_DBNAME|cut -d"=" -f2)
    MAN_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.MANUFACTURING_DBNAME|cut -d"=" -f2)
    MANUF_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep atabase.MANUFACTURING_CLASSIC_DBNAME|cut -d"=" -f2)
    MMS_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.MATERIAL_MANAGEMENT_DBNAME|cut -d"=" -f2)
    QMS_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.QUALITY_DBNAME|cut -d"=" -f2)
    TSS_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.TSS_DBNAME|cut -d"=" -f2)
    PIC_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.PICS_DBNAME|cut -d"=" -f2)
    PSL_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.LOCATION_COMMON_DBNAME|cut -d"=" -f2)
    SUP_DB=$(cat $KIWIBASE/services/sites/"$PLANTID"/current/conf/recentparametervalues.properties|grep database.SUPPLIER_MANAGEMENT_DBNAME|cut -d"=" -f2)

}

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

# Function to rotate log file
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ "$(stat -f %z "$LOG_FILE" 2>/dev/null || stat -c %s "$LOG_FILE")" -ge "$MAX_LOG_SIZE" ]; then
        mv "$LOG_FILE" "${LOG_FILE}.$(date '+%Y%m%d%H%M%S')"
        touch "$LOG_FILE"
        log_message "INFO" "${GREEN}Log file rotated due to size exceeding $MAX_LOG_SIZE bytes"
    fi
}

# Check to see if the PLANTID variable exists
check_plantid() {
    local var_name="$1"
    local var_value="${!var_name}"
    log_message "INFO" "${GREEN}Current version is: $VERSION${NC}"

    if [ -z "$var_value" ]; then
        log_message "ERROR" "${RED}$var_name is not supplied.${NC}"
	USAGE="PLANTID=maxco"
	EXAMPLE="PLANTID=maxco $0"
	USAGEDESC="This is a manditory field"
        usage
	exit 1
    fi
    
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

# Function to execute MySQL query with error handling
execute_mysql_query() {
    local query="$1"
    local db="$2"
    local result
    result=$(mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$db" -e "$query" 2>/dev/null | tail -n +2)
    if [ $? -ne 0 ]; then
        log_message "ERROR" "MySQL query failed: $query"
        return 1
    fi
    echo "$result"
    return 0
}

# Notes for the User
notes(){

    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    log_message "INFO" "${GREEN}Debug Mode, run the script like this${NC}"
    log_message "INFO" "    ${CYAN}DEBUG=Y $0 ${NC}"
    log_message "INFO" "${GREEN}##################################################################################################${NC}"
    log_message "INFO" "${GREEN}USAGE to look at machines feedback, run the script like this${NC}"
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
    local job_id="$2"
    local step_data step_line num_steps
    num_steps=$(execute_mysql_query "SELECT COUNT(DISTINCT stepNumber) 
        FROM $PCS_DB.step 
        LEFT JOIN $PCS_DB.stepalternativepcsmachine alt 
        ON step.stepAlternativePcsMachineIds=alt.objid WHERE jobId = '$job_id';")
    local scount=1
    while [ "$scount" -le "$num_steps" ]; do
	    step_line=$scount
	    step_data=$(execute_mysql_query "SELECT step.objid 
            FROM $PCS_DB.step 
            LEFT JOIN $PCS_DB.stepalternativepcsmachine alt 
            ON step.stepAlternativePcsMachineIds=alt.objid WHERE stepNumber = $scount AND jobId = '$job_id';" "$PCS_DB")
        local slcount=1
        while [ "$slcount" -le "$(echo "$step_data"|wc -l)" ]; do
            echo -e "\n${GREEN}LINEUP Entry Data for Step: ${CYAN}$step_line${YELLOW} - ObjID: ${CYAN}$(echo "$step_data"|head -$slcount|tail -1)${NC}"
            local lineup_data
            lineup_data=$(execute_mysql_query "SELECT COALESCE(le.objid,''), RPAD(COALESCE(progressStatus,''),15,' '), LPAD(COALESCE(m.oname,''),4,' '), RPAD(COALESCE(plannedQuantityProduced,''),10,' ') 
            FROM lineupentry le INNER JOIN pcsmachine pm ON le.pcsMachine=pm.objid 
            INNER JOIN $MAN_DB.machine m ON pm.machineId=m.objid WHERE step = $(echo "$step_data"|head -$slcount|tail -1);")
            if [ -z "$lineup_data" ];then
                echo -e "${RED}No LINEUP Entry Data found for StepObjectID: ${CYAN}$(echo "$step_data"|head -$slcount|tail -1)${NC}" > $PROCESSID_lineup.tm
                cat $PROCESSID_lineup.tm
            else
                echo -e "${YELLOW}Objid\tStatus\t\tMachine\tQuantity${NC}"
                echo "$lineup_data" > $PROCESSID_lineup.tm
                cat $PROCESSID_lineup.tm
            fi
            
            local linecount lcount linedata
	        linecount=$(execute_mysql_query "SELECT COUNT(le.objid) 
                FROM $PCS_DB.lineupentry le 
                INNER JOIN $PCS_DB.pcsmachine pm ON le.pcsMachine=pm.objid 
                INNER JOIN $MAN_DB.machine m ON pm.machineId=m.objid WHERE step = $(echo "$step_data"|head -$slcount|tail -1);")
            local lcount=1
            while [ "$lcount" -le "$linecount" ]; do
                linedata=$(execute_mysql_query "SELECT le.objid 
                    FROM $PCS_DB.lineupentry le 
                    INNER JOIN $PCS_DB.pcsmachine pm ON le.pcsMachine=pm.objid 
                    INNER JOIN $MAN_DB.machine m ON pm.machineId=m.objid WHERE step = $(echo "$step_data"|head -$slcount|tail -1);")
                local ldcount=1
                while [ "$ldcount" -le "$(echo "$linedata"|wc -l)" ]; do
                    echo -e "${GREEN}FEEDBACK for LINE Entry ${CYAN}$(echo "$linedata"|head -$ldcount|tail -1)${NC}"
                
                    local feedback_data
                    feedback_data=$(execute_mysql_query "SELECT RPAD(COALESCE(feedbackStatus,''),15,' '), objid, LPAD(COALESCE(FROM_UNIXTIME(startTime/1000),''),24,' '), 
                    LPAD(COALESCE(FROM_UNIXTIME(SetupCompletionTime/1000),''),24,' '), LPAD(COALESCE(FROM_UNIXTIME(finishtime/1000),''),24,' '), 
                    LPAD(COALESCE(ReportDate,''),10,' '), RPAD(COALESCE(shiftId,''),7,' '), explicitQuantityFedDuringRun, explicitQuantityProduced, derivedFeedback 
                    FROM feedback WHERE lineupentry = $(echo "$linedata"|head -$ldcount|tail -1);" "$PCS_DB")
                    if [ -z "$feedback_data" ];then
                        echo -e "\n${RED}No FEEDBACK for LINE Entry found for LineupEntryObjectId: ${CYAN}$(echo "$linedata"|head -$ldcount|tail -1)${NC}"
                        cat $PROCESSID_feedback.tm
                    else
                        echo -e "${YELLOW}Status\tOBJID\tStart Time\tSetup Time\tFinish Time\tReport_Shift\tShftId\tQ_Fed\tQ_Prd\tDerived${NC}" | expand -t22,26,30,62,94,126,142,150,158,166
                        echo "$feedback_data" > $PROCESSID_feedback.tm
                        cat $PROCESSID_feedback.tm
                    fi
                    
                    local derived_id
                    derived_id=$(execute_mysql_query "SELECT derivedFeedback FROM $PCS_DB.feedback WHERE lineupentry = $(echo "$linedata"|head -$ldcount|tail -1);")
                    local derived_data
                    derived_data=$(execute_mysql_query "SELECT RPAD(COALESCE('MDC Derived',''),15,' '), objid, COALESCE(FROM_UNIXTIME(detectedStartTime/1000),''), 
                    COALESCE(FROM_UNIXTIME(detectedSetupFinishTime/1000),''), COALESCE(FROM_UNIXTIME(detectedFinishTime/1000),''), 
                    '          ' ReportDate, '        ' ShiftId, detectedRunQuantityFed, detectedQuantityProduced, ' ' derivedFeedback 
                    FROM derivedfeedback WHERE objid = '$derived_id';" "$PCS_DB")
                    if [ -z "$derived_data" ];then
                        echo -e "\n${RED}No DIREVEDFEEDBACK for LINE Entry found for LineupEntryObjectId: ${CYAN}$(echo "$linedata"|head -$ldcount|tail -1)${NC}"
                        cat $PROCESSID_derived.tm
                    else
                        echo "$derived_data" > $PROCESSID_derived.tm
                        cat $PROCESSID_derived.tm
                    fi
                ldcount=$((ldcount + 1))
                done                
            lcount=$((lcount + 1))
            done
        slcount=$((slcount + 1))
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
    local date
    date=$(date)

    case "${action,,}" in
        "close")
            log_message "INFO" "Completing $order_num Lineupentry:$linedata Step:$step_data"
            echo -e "${GREEN}$date: Completing $order_num Lineupentry:$linedata Step:$step_data${NC}"
            execute_mysql_query "UPDATE step SET progressStatus='COMPLETED' WHERE objid=$step_data;" "$PCS_DB"
            execute_mysql_query "UPDATE lineupentry SET progressStatus='COMPLETED' WHERE objid=$linedata;" "$PCS_DB"
            ;;
        "open")
            log_message "INFO" "Opening $order_num Lineupentry:$linedata Step:$step_data"
            echo -e "${GREEN}$date: Opening $order_num Lineupentry:$linedata Step:$step_data${NC}"
            execute_mysql_query "UPDATE step SET progressStatus='NOT_SCHEDULED' WHERE objid=$step_data;" "$PCS_DB"
            execute_mysql_query "UPDATE lineupentry SET progressStatus='NOT_SCHEDULED' WHERE objid=$linedata;" "$PCS_DB"
            ;;
        "run")
            local alter_data
            alter_data=$(execute_mysql_query "SELECT stepAlternativePcsMachineIds FROM step LEFT JOIN stepalternativepcsmachine alt ON step.stepAlternativePcsMachineIds=alt.objid WHERE jobId = '$job_id' AND step.stepNumber='$step';" "$PCS_DB" | grep -v "objid" | tr "," "\n")
            echo "$alter_data" > $PROCESSID_alter.tm
            while IFS= read -r alter; do
                if [ -n "$alter" ]; then
                    execute_mysql_query "UPDATE stepalternativepcsmachine SET runDuration='$runduration' WHERE objid = '$alter';" "$PCS_DB"
                    execute_mysql_query "UPDATE stepalternativepcsmachine SET runDurationSource='USER' WHERE objid = '$alter';" "$PCS_DB"
                    log_message "INFO" "Updating $order_num speed on Alternative:$alter Step:$step to Run:$runduration USER"
                    echo -e "${GREEN}$date: Updating $order_num speed on Alternative:$alter Step:$step to Run:$runduration USER${NC}"
                fi
            done < $PROCESSID_alter.tm
            ;;
        *)
            log_message "ERROR" "Invalid action: $action"
            echo -e "${RED}Invalid action: $action${NC}"
            exit 1
            ;;
    esac
}

# Main function
main() {
    # Rotate log
    #rotate_log
    #cd $HOME
    #Validate any variables that MUST exist
    check_plantid "PLANTID"
    get_environment

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

    # Verify Heatlh CSC
    health_check_csc_order
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

    #Verify PCS
    if [[ -n "$ORDERNUMBER" || -n "$ORDERID" || -n "$JOBID" ]];then
       
       log_message "INFO" "${YELLOW}Starting PCS verification task${NC}"
       read -r order_id order_num job_id < <(verify_pcs_order "$ORDERID" "$ORDERNUMBER" "$JOBID")
       # Display order details
       display_order_details "$order_id" "$order_num" "$job_id"
       # Handle step details if provided
       display_step_details "$num_steps" "$job_id"
       # Handle actions for updates and ect.. if provided
       if [ -n "" ]; then
          local step_data
          step_data=$(head -n 1 $PROCESSID_steps.tm | cut -c1-6 | tr -d " ")
          local linedata
          linedata=$(head -n 1 $PROCESSID_lineup.tm | cut -c1-6 | tr -d " ")
          handle_order_action "$order_num" "$step_data" "$linedata" "$3" "$4" "$job_id" "$2"
       fi
       log_message "INFO" "${GREEN}PCS Order verification completed for $order_num${NC}"
    fi

    #log_message "INFO" "${YELLOW}Cleaning up my working files called $PROCESSID_*.tm${NC}"
    #rm $PROCESSID_*.tm
    #log_message "INFO" "${GREEN}Cleanup completed${NC}"
    log_message "INFO" "${GREEN}Finished Health Check on the VUE systems${NC}"
    return 0
}

# Trap errors
trap 'log_message "ERROR" "Script terminated unexpectedly at line $LINENO"; exit 1' ERR

# Execute main function
main "$@"
exit $?
