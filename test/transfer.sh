#!/bin/sh

LOGD="filesystempath/logs/`date '+%Y/%m/%d'`"
if [ ! -d $LOGD ]; then
	mkdir -p $LOGD
	if [ -d $LOGD ]; then
		cd $LOGD
		exit 1
	fi
fi
	
LOG="${LOGD}/transfer_`date '+%H%M'`.log"
TMP="${LOG}.$$"

START="Starting $0 `date`"
cd /local/installpath/bin && ./transfer.pl --verbose 2>&1 | tee -a ${TMP} 
STOP="Done $0 `date`" 

if [ -s $TMP ]; then
	echo $START >> $LOG
	/usr/bin/cat $TMP >> $LOG
	echo $STOP >> $LOG
fi

# Remove old files
/local/installpath/bin/rmold.pl

/usr/bin/rm -f $TMP
