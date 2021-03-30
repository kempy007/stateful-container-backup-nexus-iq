#!/bin/bash -x
#
# Author: Martyn Kemp
# Date: 23/03/2021
# Purpose: Allow consistent backup for stateful container app.
#


STARTHOUR=23
STARTMIN=50
WINDOW=10
export OBJECTSTORE=s3 # s3 / azure
export AWS_ACCESS_KEY_ID=minio
export AWS_SECRET_ACCESS_KEY=minio123
export AZURE_ACCOUNT_NAME=REDACTED # storage account name
export AZURE_ACCOUNT_KEY=REDACTED # storage account key
export RESTIC_PASSWORD=REDACTED # pw for storage encryption
#export RESTIC_PASSWORD_COMMAND=$(echo $RESTIC_PASSWORD)
export BACKUPURL= # {bucketname}:/{folder} #http://minio.velero.svc:9000/resticiq
export TEAMSWH=REDACTED # MS Teams webhook teams group channel

# check date/time within schedule, execute backup func, else execute main program.
# grab disk usage and send somewhere
checkSchedule() {
    THISHOUR=$(date +%H)
    THISMIN=$(date +%M)
    if [ "$THISHOUR" -eq "$STARTHOUR" ]
    then
      if [ "$THISMIN" -ge "$STARTMIN" ]
      then
        if [ "$THISMIN" -le "$(($STARTMIN + $WINDOW))" ]
        then
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    else
      return 1
    fi
}

backup() {
    echo "Starting Backup"
    cd /sonatype-work
    # download our tinyweb server 1.6mb upx and stripped is still huge
    TWSHA256=1EBA09AEFA9CA09A69402FE51F97580A95656AC8327BE09631B61DE58816B8A0
    TWRESULT=$(echo $TWSHA256" tinyweb" | sha256sum -c)
    RETURNTW=$?
    if [ "$RETURNTW" -ne 0 ]
    then
      curl -OL https://github.com/kempy007/healthcheck-tinyweb/releases/download/v0.1.0/tinyweb
      chmod 744 tinyweb
    fi
    TWRESULT2=$(echo $TWSHA256" tinyweb" | sha256sum -c)
    RETURNTW2=$?
    if [ "$RETURNTW2" -eq 0 ]
    then
      exec ./tinyweb &
      export TW_PID=$!
    else
      echo "Error with tinyweb, either corrupt/missing"
    fi
    

    # Will download restic to the PV, to save bandwidth and time.
    RESTICSHA256=7B29C08BE9FC8F3E81E311CA2E1363D964884B6A89DCA2F6CD5313CD2C1087AD
    RESULT=$(echo $RESTICSHA256" restic" | sha256sum -c)
    RETURNC=$?
    # restic: OK
    # restic: FAILED (with return code 1)
    # restic: FAILED open or read
    if [ "$RETURNC" -ne 0 ]
    then
      curl -OL https://github.com/kempy007/restic-upx/releases/download/v0.12.0/restic
      chmod 744 restic
    fi
    RESULT2=$(echo $RESTICSHA256" restic" | sha256sum -c)
    RETURN2=$?
    if [ "$RETURN2" -eq 0 ]
    then
      # Need to open webports incase process takes longer than 30s so healthchecks don't shut us down
      ./restic -r $OBJECTSTORE:$BACKUPURL snapshots
      REPOINIT=$?
      if [ "$REPOINIT" -ne 0 ]; then 
        ./restic -r $OBJECTSTORE:$BACKUPURL init
      fi
      ./restic -r $OBJECTSTORE:$BACKUPURL backup /sonatype-work
      ./restic -r $OBJECTSTORE:$BACKUPURL forget --prune --keep-daily 7 --keep-monthly 12 --keep-yearly 3
    else
      echo "Error with restic, either corrupt/missing"
    fi
    echo "###########################"
    echo "#####  storage stats  #####"
    echo "###########################"
    df -h
    TEST=$(df -h | egrep [7-9][0-9]%) # has formatting issue in teams post, cuts it off.
    # Close our tinyweb healthcheck helper
    kill $TW_PID
    postTeamsMsg $TEST
    echo "Backup complete"
}

runProgram() {
    echo "Starting Program"
    # Runs original program entrypoint
    cd /opt/sonatype/nexus-iq-server/
    if [ -f "start-nexus-iq-server.sh" ] 
    then 
      export RUNSCRIPT="./start-nexus-iq-server.sh" 
    fi
    if [ -f "start.sh" ] 
    then
      export RUNSCRIPT="./start.sh" 
    fi
    exec $RUNSCRIPT &
    #ping localhost -t &

    # Gets the PID of program
    RUN_PID=$!
    echo "Program started with PID: "$RUN_PID

    # debounce our backup scheduler from looping
    DURATION=$(($WINDOW+3))m
    sleep $DURATION

    echo "Entering wait loop for next schedule"
    touch .runcmd
    while [ -f ".runcmd" ]
    do
    if checkSchedule; then rm .runcmd && stopProgram $RUN_PID; fi;
    sleep 30
    echo "Slept 30"
    done
}

stopProgram() {
    echo "Stopping Program"
    RUN_PID=$1
    # Graceful Kill the process (sigterm):
    kill $RUN_PID
    sleep 10

    # Kills the process (sigkill):
    kill -9 $RUN_PID
}

postTeamsMsg() {
  WEBHOOK_URL=$TEAMSWH
  TITLE="Nexus IQ Backup"
  COLOR=0072C6
  TEXT="Backup executed $(date)   \r\n "'```'" $1 "'```'
  # Convert formating.
  MESSAGE=$( echo ${TEXT} | sed 's/"/\"/g' | sed "s/'/\'/g" )
  JSON="{\"title\": \"${TITLE}\", \"themeColor\": \"${COLOR}\", \"text\": \"${MESSAGE}\" }"

  # Post to Microsoft Teams.
  curl -H "Content-Type: application/json" -d "${JSON}" "${WEBHOOK_URL}"
}

if checkSchedule
then 
  backup
else
  echo "Not in backup window, skipping backup"
fi

runProgram
