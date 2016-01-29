#/bin/bash

LASTLOGFILE="/tmp/lastlogdate"
LOGFILE="/var/log/syslog"
PERIOD=${1-1}

#LASTDATE="Jan 29 16:38:01"
#LASTDATE=$(date +"%b %_d %T")
save_last_date() {
    echo $(tail -n1 $LOGFILE | cut -b-15) > $LASTLOGFILE   
    echo LAST DATE in LOG - $(tail -n1 $LOGFILE | cut -b-15)
    echo LAST DATE in file - $(cat $LASTLOGFILE)
    echo ""
}

while true 
do
    LASTDATE=$(cat $LASTLOGFILE)

    if [ -z "$LASTDATE" ]; then
        save_last_date
        exit 0
    fi

    LASTNUM=$(sed -n "/${LASTDATE}/=" $LOGFILE | tail -n1)
    echo $(sed -n "/${LASTDATE}/=" $LOGFILE)
    DIFF=$(wc -l $LOGFILE | egrep -o "[0-9]+")-$LASTNUM

    DIFFNUM=$(( DIFF ))
    echo "$DIFF"
    echo "==> $DIFFNUM <== NEW LOG MESSAGES"

    save_last_date


    sleep $PERIOD
done


