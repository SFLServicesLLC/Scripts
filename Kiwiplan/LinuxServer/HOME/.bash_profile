#!/bin/bash
#Type:Utility
#########################################################
# Script:
#
# This is used for logging into a test server
# 
# Created by:
# Steve Ling
#########################################################
# Revision
#
# 2025-01-26 SFL Initial revision
# 2025-07-26 SFL Added more logic for display
# 2025-08-17 SFL Added more logic around adding and deleting sites
#
#########################################################
#
# Environment:
#
umask 002
#trap 'echo "Caught Ctrl+C"; exit 0' SIGINT
export KIWIBASE=/KIWI
export KWSQL_USER=${KWSQL_USER:-kiwisql}
export MYSQL_PWD=${MYSQL_PWD:-800486kiwi}
DBHOST=localhost
VERSION=1.4
#
# Variables
variables() {
VUEBASE=$KIWIBASE/services
VUESITES=$VUEBASE/sites
REV=$KIWIBASE/rev
REVS=$REV/map
MREVS=$REV/mes
DATASETS=/KIWI/backups
}
#
# Define colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'
FLASH='\033[5m'
#
# Define log file
LOG_FILE="Log$(date +"%Y%m%d_%H%M%S").log"
#
# Logging function
log() {
  local message="$1"
  local level="$2" # Optional: INFO, WARNING, ERROR
  local color="$3"

  # Timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  # Log message with level and timestamp
  echo -e "${color}${message}${NC}" | tee -a "$LOG_FILE"
  #echo -e "${color}${message}${NC}" >> "$LOG_FILE"
  echo "[${timestamp}] [${level}] ${message}" | logger
}
#
# Display banner
banner(){
clear
log "Version $VERSION" "INFO" "${BLUE}${BOLD}"
log "=========================================" "INFO" "${GREEN}${BOLD}"
log "|  Welcome to the Test/Dev Environment  |" "INFO" "${GREEN}${BOLD}"
log "|                                       |" "INFO" "${GREEN}${BOLD}"
log "| You are in the server:                |" "INFO" "${GREEN}${BOLD}"
log "  $(hostname) " "INFO" "${YELLOW}${BOLD}"
log "=========================================" "INFO" "${GREEN}${BOLD}"
echo ""
log "Classic Revisions are located $REVS" "INFO" "${BLUE}${BOLD}"
log "MES Revisions are located $MREVS" "INFO" "${BLUE}${BOLD}"
log "Backups are located $DATASETS" "INFO" "${YELLOW}${BOLD}"
echo ""
}
#
# Check 
checkVariables() {
if [ ! -d "$REVS" ];then
        log "$REVS does not exist Rev" "ERROR" "${RED}${BOLD}${FLASH}"
        sleep 5
        return 1
fi
#
if [ ! -d "$MREVS" ];then
        log "$MREVS does not exist Mrev" "ERROR" "${RED}${BOLD}${FLASH}"
        sleep 5
        return 1
fi
#
if [ ! -d "$DATASETS" ];then
        log "$DATASETS does not exist Datasets" "ERROR" "${RED}${BOLD}${FLASH}"
        sleep 5
        return 1
fi
}
#
# Main Menu
main_menu(){
# Main Menu
  variables
  banner
  echo ""
  log "A) Add Site" "INFO" "${GREEN}${BOLD}"
  log "D) Delete Site." "INFO" "${GREEN}${BOLD}"
  log "R) Restore Data" "INFO" "${GREEN}${BOLD}"
  log "S) Select Site" "INFO" "${GREEN}${BOLD}"
  log "U) Update /KIWI/corp/bin/bash_profile script from repo" "INFO" "${RED}${BOLD}"
  echo ""
  log "X) Exit" "INFO" "${BLUE}""${BOLD}"
  echo ""
  echo -en "${YELLOW}""${BOLD}" "Default [S] : "
#  read -t 10 choice #Time out of 10 sec
  read choice
  log choice
  case "$choice" in
    "A"|"a")
            log "Chose option A" "INFO" "${YELLOW}""${BOLD}"
            site_add
    ;;
    "D"|"d")
            log "Chose option D" "INFO" "${YELLOW}""${BOLD}"
            site_delete
    ;;
    "R"|"r")
            log "Chose option R" "INFO" "${YELLOW}""${BOLD}"
            data_restore
    ;;
    "S"|"s")
            log "Chose option S" "INFO" "${YELLOW}""${BOLD}"
            site_select
    ;;
    "U"|"u")
            log "Chose option U" "INFO" "${YELLOW}""${BOLD}"
            update_scripts
    ;;
    "X"|"x")
            log "Exiting..." "INFO" "${YELLOW}""${BOLD}"
            exit 0
    ;;
    *)
      site_select
      return 0
    ;;
  esac

}
#
# Update Scripts
update_scripts(){
  UPDFILE=bash_profile
  CURRENTVER=$(cat /KIWI/corp/bin/$UPDFILE |grep VERSION= | cut -d'=' -f2)
  log "Getting the most recent bash_profile script" "INFO" "${YELLOW}""${BOLD}"
  log "Downloading from remote FTP server"
  cd "$HOME || exit" || exit
  UPDFILE=bash_profile
  lftp -u anonymous,"" ftp://ftp.sflservicesllc.io -e "get $UPDFILE; bye"
  bye 
  EOF
  if [ $? -ne 0 ]; then
    log "Failed to download new script." "ERROR" "${RED}""${BOLD}"
    sleep 5
    main_menu 
  else
    UPDVER=$(cat $UPDFILE |grep VERSION= | cut -d'=' -f2)
  fi
  if [ "$CURRENTVER" -lt "$UPDVER" ];then
     log "Updating script..." "INFO" "${GREEN}""${BOLD}"
     cp -f "$UPDFILE" "$KIWIBASE/corp/bin"
     if [ $? -ne 0 ]; then
        log "Failed to update script." "ERROR" "${RED}""${BOLD}"
        sleep 5
        rm -f "$UPDFILE"
        main_menu
     fi
     chmod +x "$KIWIBASE/corp/bin/$UPDFILE"
     rm -f "$UPDFILE"
     log "Script updated successfully." "INFO" "${BLUE}""${BOLD}"
  else
     log "Script does not need to be update" "INFO" "${GREEN}""${BOLD}"
     rm -f "$UPDFILE"
  fi
}
#
# Add a Site
site_add(){
  log "Looking for MES licences that are in the $MREVS folder" "INFO" "${YELLOW}""${BOLD}"
  if find $MREVS/* -maxdepth 1 -type f|grep -i licence |sort>/dev/null 2>&1; then
    #log `find $MREVS/* -maxdepth 1 -type f|grep -e licence |sort` "INFO" ${BLUE}${BOLD}
    find $MREVS/* -maxdepth 1 -type f|grep -i licence |sort
    log "Found the following licenses" "INFO" "${GREEN}""${BOLD}"
  else
    log "No licenses were found" "WARNING" "${YELLOW}""${BOLD}"
  fi
  log "If you are going to install a MES revision and you do not see your license:" "INFO" "${GREEN}""${BOLD}"
  log "Please quit and copy your license first in the $MREVS revision you wish to use" "INFO" "${YELLOW}""${BOLD}"
  log "Continue Y/N ?" "INFO" "${BLUE}""${BOLD}""${FLASH}"
  read choice
  case "$choice" in
    Y|y|1)
        ;;
    *)
        log "You did not choose Y,y or 1 to continue:" "INFO" "${YELLOW}""${BOLD}"
        sleep 3
        banner
        main_menu
        ;;
  esac
  log "Preparing to add a site to the environment" "INFO" "${YELLOW}""${BOLD}"
  #echo -en ${GREEN}${BOLD} "Enter 4 character site name : "
  log "Enter 4 character site name : " "INFO" "${GREEN}""${BOLD}"
  read NEW_SITE

  if [ ${#NEW_SITE} -lt 4 -o -eq 4 ];then
     log "You have to use 4 or less characters" "ERROR" "${RED}""${BOLD}"
     sleep 3
     main_menu
  fi
  if [ -z "$NEW_SITE" ];then
    log "You have not entered a site name with a minimum of 4 charaters" "ERROR" "${RED}""${BOLD}"
    sleep 3
    main_menu
  fi
  if find /KIWI/ -maxdepth 1 -type d -name site_"${NEW_SITE}" | grep -q .; then
      log "The site you entered $NEW_SITE already exist" "ERROR" "${RED}""${BOLD}"
      sleep 3
      main_menu
  fi
  REVS=$(find /KIWI/rev/map/* -maxdepth 0 -type d| sort)
  PS3="Select MAP revision for $NEW_SITE : "
  select REV in $REVS
  do
    if [ ! -d "/KIWI/rev/site_$NEW_SITE" ]; then
       ln -s "$REV" $KIWIBASE/rev/site_"$NEW_SITE"
    fi
    mkdir -p $KIWIBASE/site_"$NEW_SITE"
    ln -s $KIWIBASE/rev/site_"$NEW_SITE"/bin $KIWIBASE/site_"$NEW_SITE"/bin
    ln -s $KIWIBASE/rev/site_"$NEW_SITE"/progs $KIWIBASE/site_"$NEW_SITE"/progs
    ln -s $KIWIBASE/rev/site_"$NEW_SITE"/scp $KIWIBASE/site_"$NEW_SITE"/scp
    ln -s $KIWIBASE/rev/site_"$NEW_SITE"/sql $KIWIBASE/site_"$NEW_SITE"/sql
    break
  done
  DATATYPES="MySQL ISAM"
  select DATATYPE in $DATATYPES
  do
    log "Choose the correct data type" "INFO" "${GREEN}""${BOLD}"
    break
  done
  gen_kidds
  if [ "$DATATYPE" = "MySQL" ]; then
    log "Adding the MySQL" "INFO" "${GREEN}""${BOLD}"
    install_mysql new
  else
    log "Adding the ISAM" "INFO" "${GREEN}""${BOLD}"
    install_isam new
  fi
  if [ ! "$DATATYPE" = "ISAM" ]; then
    log "Adding the JAVA envirnoment requirements" "INFO" "${GREEN}""${BOLD}"
    mkdir -p $KIWIBASE/site_"$NEW_SITE"/site/bin
    mkdir -p $KIWIBASE/site_"$NEW_SITE"/site/dat
    if [ ! -d $KIWIBASE/services  ];then
       mkdir -p $KIWIBASE/services/
    fi
    cd $KIWIBASE || exit
    if [ ! -d $KIWIBASE/java  ];then
       ln -s $KIWIBASE/services java
    fi
    mkdir -p $KIWIBASE/services/sites/"$NEW_SITE"/
    MREVS=$(find $KIWIBASE/rev/mes/* -maxdepth 0 -type d| sort)
    PS3="Select MES revision for $NEW_SITE : "
    select MREV in $MREVS
    do
      cd /$KIWIBASE/services/sites/"$NEW_SITE"/ || exit
      mkdir -p $(basename "$MREV")
      ln -s $(pwd)/$(basename "$MREV") current 
      mkdir -p $KIWIBASE/services/sites/"$NEW_SITE"/current/conf
      mkdir -p $KIWIBASE/services/sites/"$NEW_SITE"/current/conf/kiwiplan/roadgrids
      ln -s $KIWIBASE/services/maps/roadgrids/osm-gh $KIWIBASE/services/sites/"$NEW_SITE"/current/conf/kiwiplan/roadgrids/osm-gh
      mkdir -p $KIWIBASE/services/sites/"$NEW_SITE"/current/logs
      break
    done
    log "Added $NEW_SITE to the environment type $ENVTYPE" "INFO" "${BLUE}""${BOLD}"
    log "Setting the $NEW_SITE environment from $KIWIBASE/corp/bin/stdprofile" "INFO" "${YELLOW}""${BOLD}"
    export PLANTID=$NEW_SITE
    export KIWI=$KIWIBASE/site_$PLANTID
    export EXEC="continue"
    . /KIWI/corp/bin/stdprofile
    log "Now will add the MES environment for $NEW_SITE" "INFO" "${BLUE}""${BOLD}"
    cd "$MREV || exit" || exit
    REVBASE=$(basename "$MREV")
    log "This will take some time to decompress and will start the install" "INFO" "${BLUE}""${BOLD}""${FLASH}"
    tar zxvf mes_"$REVBASE".tar.gz
    ./mes-"$REVBASE".sh
    log "Running the importdata script for the $NEW_SITE environment and looking for them in $DATASETS" "INFO" "${GREEN}""${BOLD}"
    cd "$DATASETS || exit" || exit
    $KIWIBASE/corp/bin/importdata
  else
    log "Added $NEW_SITE to the environment type $ENVTYPE" "INFO" "${BLUE}""${BOLD}"
    log "Setting the $NEW_SITE environment from $KIWIBASE/corp/bin/stdprofile" "INFO" "${YELLOW}""${BOLD}"
    export PLANTID=$NEW_SITE
    export KIWI=$KIWIBASE/site_$PLANTID
    export EXEC="continue"
    . /KIWI/corp/bin/stdprofile
  fi
  main_menu
}

site_delete(){
  if ! ls $KIWIBASE/site_* >/dev/null 2>&1; then
        echo "Sites do not exist"
        sleep 2
        main_menu
  fi
  PS3="Choose site or 0 for main menu: "
  SITES=$(ls -d $KIWIBASE/site_* | cut -b 12-)
  if "$MAPDATA"/kwsql >/dev/null 2>&1; then
        CLASSIC=$(grep "DATA=" "$MAPDATA"/kwsql|cut -d"=" -f2)
  else
        CLASSIC=""
  fi
  select SITE in $SITES
  do
    log "Are you sure you want to delete /KIWI/site_$SITE (Y/N)?" "INFO" "${BLUE}""${BOLD}""${FLASH}"
    read choice
      case "$choice" in
      "Y"|"y")
        echo "Deleting the Classic Site Folder"
        if [ ! -n "$CLASSIC" ]; then
                find $KIWIBASE/site_"$SITE"/ -name kwsql -exec mysql -e "drop database $SITE_map" \;;
        fi
        echo "Deleting the Kiwi Site Folder"
        rm -rf $KIWIBASE/site_"$SITE"
        echo "Deleting the Rev Site Folder"
        rm -f $KIWIBASE/rev/site_"$SITE"
        echo "Deleting the Jave Site Folder"
        rm -rf $KIWIBASE/services/sites/"$SITE"/
        echo "Deleting the Web Folder"
        rm -rf $KIWIBASE/services/web/"$SITE"
      ;;
      *)
        main_menu
      ;;
      esac
    log "We deleted the /KIWI/site_$SITE" "INFO" "${YELLOW}""${BOLD}"
    sleep 3
    break
  done
  main_menu
}

data_restore() {
  if [ ! -d $KIWIBASE/site_*  ];then
     log "Sites do not exists"
     sleep 2
     main_menu
  fi 
  PS3="Choose site or 0 for main menu:"
  SITES=$(ls -d $KIWIBASE/site_* | cut -b 12-)
  select NEW_SITE in $SITES
  do
    echo -n "Are you sure you want to overwrite data for /KIWI/site_$NEW_SITE (Y/[N])?"
    read choice
      case "$choice" in
      "Y"|"y")
        rm -rf $KIWIBASE/site_"$SITE"/data_"$NEW_SITE"/*
      
        echo "Select data source : "
        echo ""
        echo "I) ISAM"
        echo "M) MySQL"
        echo ""
        echo -n "Default [I] : "
        read choice
        case "$choice" in
        "M"|"m")
          install_mysql restore
        ;;
        *)
          install_isam restore
        ;;
       esac
       ;;
       *)
         main_menu
       ;;
      esac
    break
  done
  main_menu
}

install_isam() {
  if [ ! -f $KIWIBASE/backups/*.tar.gz ];then
     log "ISAM Backup files do not exist"
     sleep 2
     return
  fi
  #DATASETS=`find $KIWIBASE/backups/*.tar.gz`
  PS3="Select data for $NEW_SITE : "
  select DATASET in $(find "$DATASETS"/*.tar.gz)
    do
      if [ "$1" == "new" ]; then      
        log "Extracting the $DATASET" "INFO" "${GREEN}""${BOLD}"
        mkdir -p $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"
        tar -zxvf "$DATASET" -C $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"
      fi
      if [ "$1" == "restore" ]
        then
        log "Restore not implemented yet" "INFO" "${RED}""${BOLD}"
        sleep 5
        break
        find $KIWIBASE/site_"$NEW_SITE"/ -name kwsql -exec rm {} \;;
        mkdir -p $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"
        tar -zxvf "$DATASET" -C $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"
        SCR_DIR=$(basename "$(tar -ztf "$DATASE" | head -n 1)")
      fi
      break
    done  
}

install_mysql() {
if [ -f $KIWIBASE/backups/*.sql.gz ];then
   DATASETS=$(find $KIWIBASE/backups/*.sql.gz)
   PS3="Select data for $NEW_SITE : "
   select DATASET in $DATASETS
   do 
      if [ "$1" == "restore" ];then
          log "Checking to ensure the database is not in use" "INFO" "${YELLOW}""${BOLD}"
          sleep 2
          mysqladmin processlist | grep -v _master | egrep -q "$DATASET"
          if [ $? -eq 1 ] ; then
            mysql -e "drop database $($NEW_SITE_map)"
          logo "Dropping old databases""INFO" "${YELLOW}""${BOLD}"
          sleep 2
          else
            echo "Destination database is in use. Please try again later."
            read error
          fi
      else
        mkdir -p $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"
      fi  
      logo "Creating new database." "INFO" "${YELLOW}""${BOLD}"
      sleep 2
      mysql -e "create database $NEW_SITE_map"
      log "Restoring database now." "INFO" "${YELLOW}""${BOLD}"
      sleep 2
      zcat "$DATASET" | grep -v "CREATE DATABASE" | mysql "$NEW_SITE_map"
      mysql -e "grant all on $NEW_SITE.* to 'kiwisql'@'localhost' identified by '800486kiwi'"
     break
   done
else
   log "SQL Backup files do not exist" "INFO" "${YELLOW}""${BOLD}"
fi
   if [ ! -d $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE" ]; then
        echo "Creating the site Data Folder"
        mkdir -p $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"
   fi
log "Creating the kwsql file" "INFO" "${YELLOW}""${BOLD}"
touch $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"/kwsql
echo "DATA=""${NEW_SITE}""_map" > $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"/kwsql
echo "HOST=localhost" >> $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"/kwsql
echo "INTERFACE=sql" >> $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"/kwsql
echo "USER=kiwisql" >> $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"/kwsql
echo "PASSWORD=800486kiwi" >> $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"/kwsql 
#   echo "PASSWORDX=2o5tP2P8uX4WMp4xsjVnK8DGX5uYrwBz" >> /KIWI/site_$NEW_SITE/data_$NEW_SITE/kwsql   
echo "LOG=error" >> $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"/kwsql
echo "LOGPID=1" >> $KIWIBASE/site_"$NEW_SITE"/data_"$NEW_SITE"/kwsql
}

gen_kidds() {
  log "Adding and setting up the KIDSENV file" "INFO" "${GREEN}""${BOLD}"
  rm -f $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  touch $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "SHELL=/bin/sh" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "TERM=vt100" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIDSDEBUG=4" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIDSLOGDIR=/tmp" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIDSLOGLEVEL=4" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIDSLOGMAX=1000000" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "#Settings can be error, query" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KWSQL_LOG=query" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KWLOCK_TIME_LOG=15" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KWLOCK_TIME_COUNT=15" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIWI_NO_CATCH_HUP=1" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIWI_LOCK_NOPID=1" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIWISITE=$NEW_SITE" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIWI=/KIWI/site_$NEW_SITE" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "DATA=\$KIWI/data_$NEW_SITE" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "WORK=\$KIWI/work/$LOGNAME" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "BIN=\$KIWI/bin/" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "PROGS=\$KIWI/progs/" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "SCP=\$KIWI/scp/" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "SITEBIN=\$KIWI/site/bin" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "SITEDAT=\$KIWI/site/dat" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "SQL=\$KIWI/sql" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIDSLOGDIR=\$KIWI/work/$LOGNAME" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KWSQL_COMMONDIR=\$KIWI/data_$NEW_SITE" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "LD_LIBRARY_PATH=\$PROGS" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KWSQL_USER=kiwisql" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KWSQL_PASS=800486kiwi" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "KIWISEA=.:\$DATA:\$SITEDAT:\$SITEBIN:\$PROGS:\$BIN:\$SCP:\$SQL"  >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
  echo "PATH=\$PATH:.:\$SITEDAT:\$SITEBIN:\$CORPBIN:\$PROGS:\$BIN:\$DAT" >> $KIWIBASE/site_"$NEW_SITE"/KIDSENV
}

setup_counter () {
  cd $KIWIBASE || exit
  if [ ! -d $KIWIBASE/"$SITE_counter" ];then
        mkdir -p $KIWIBASE/"$SITE_counter"
  fi
  ln -s $KIWIBASE/site_"$NEW_SITE"/work/mdcxmt "$SITE_counter"
}

site_select(){
  if [ ! -d $KIWIBASE/site_*  ];then
     log "Sites do not exists" "ERROR" "${RED}""${BOLD}""${FLASH}"
     sleep 5
     main_menu
  fi
    banner
    PS3="Choose site or 0 for main menu: "
    SITES=$(ls -d $KIWIBASE/site_* | cut -b 12-)
    log "Sites that are currently running:" "INFO" "${YELLOW}""${BOLD}"
    for j in $SITES
        do
                RUNNING=$(ps -ef | grep tomcat | grep -i "$j" | cut -b 133-136)
                if [ ! "$RUNNING" = "" ];then
                        log "${GREEN}${BOLD}Site ${BLUE}${BOLD}$j ${GREEN}${BOLD}is already running" "INFO" "${BLUE}""${BOLD}"
                fi
        done
    echo ""
    log "Site Ports" "INFO" "${YELLOW}""${BOLD}"
    for s in $SITES
        do
                if [ -e $KIWIBASE/services/sites/"$s"/current/conf/recentparametervalues.properties ];then
                        PORTS=$(cat $KIWIBASE/services/sites/"$s"/current/conf/recentparametervalues.properties|grep OFFSET|cut -d"=" -f2)
                        PORTEXT=$(expr 8080 + "$PORTS")
                fi
                MAPREV=$(readlink $REV/site_"$s" | sed "s|^${REVS}/||")
                VUEREV=$(readlink $VUESITES/"$s"/current | sed "s|^${VUESITES}/$s/||")
                if [ ! -z "$PORTS" ];then
                  log "${GREEN}${BOLD}Site ${BLUE}${BOLD}$s ${GREEN}${BOLD}has a port of ${BLUE}${BOLD}$PORTEXT ${GREEN}${BOLD}and MAP Rev of ${BLUE}${BOLD}$MAPREV ${GREEN}${BOLD}and MES Rev of ${BLUE}${BOLD}$VUEREV" "INFO" "${BLUE}""${BOLD}"
                else
                  log "${GREEN}${BOLD}Site ${BLUE}${BOLD}$s ${GREEN}${BOLD} and MAP Rev of ${BLUE}${BOLD}$MAPREV" "INFO" "${BLUE}""${BOLD}"
                fi
        done
    echo ""
    log "Sites that are available or 0 to return to main menu:" "INFO" "${YELLOW}""${BOLD}"
    select SITE in $SITES
    do
      if [[ -z "$SITE" ]];then
         banner
         main_menu
      fi

      export PLANTID=$SITE
      export KIWI=$KIWIBASE/site_$PLANTID
      export EXEC="kiwimenu menu=support"

      # Check id kwsql file exists
      if [ -e $KIWIBASE/site_"$SITE"/data_"$SITE"/kwsql ];then
        export CLASSIC=$(grep "DATA=" $KIWIBASE/site_"$SITE"/data_"$SITE"/kwsql|cut -d"=" -f2)
        # MySQL query
        QUERY="SELECT SUBSTRING(xl_body,30,39) FROM XLATEP WHERE xl_system='GEN' AND xl_prefix='EE' OR xl_prefix='EI'"
        # Execute query and store results
        results=$(mysql -h "$DBHOST" -u "$MYSQLUSER" -p"$MYSQLPASS" -D "$CLASSIC" -e "$QUERY" --batch --silent)
      fi

      # Check if query was successful
      if [ $? -ne 0 ]; then
        log "Error executing MySQL query" "ERROR" "${RED}""${BOLD}""${FLASH}"
        sleep 5
        banner
        main_menu
      fi

      # Read results line by line
      while IFS=$'\t' read -r -a columns; do
        if [ -n "${columns[0]}" ]; then
          mkdir -p "${columns[0]}"
          if [ $? -eq 0 ]; then
            log "Created the following folder : ${columns[0]}" "INFO" "${BLUE}""${BOLD}"
          else
            log "Failed to create folder : ${columns[0]}" "ERROR" "${RED}""${BOLD}"
          fi
        else
          log "Empty folder name in first column" "WARNING" "${YELLOW}""${BOLD}"
        fi
      done <<< "$results"

      setup_counter
      . $KIWIBASE/corp/bin/stdprofile
      break
    done
}
#
# Execute
variables
checkVariables
main_menu
