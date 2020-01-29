#!/bin/bash

# Purpose: a simple stale NFS monitor script which mails an alert (for now)
# Script has been modified to work only o Linux
# Author: Gratien D'haese
# License: GPL v3


PATH=/usr/xpg4/bin:/usr/bin:/bin:/usr/local/bin:/usr/sbin:/sbin:.
PROGRAM="$0"
PRGNAME=$(basename $0)
TSEC=10		# default 10 seconds (overrule with -t option)
DEBUG=		# default off (set to "1" to enable debugging)
mailusr=root    # default destination
LOGFILE="/var/tmp/${PRGNAME%.*}-$(date +%Y%m%d-%H:%M).log"
version=2.0

function is_num
{
    if expr $( echo $1 | cut -d. -f1 ) + 0 >/dev/null 2>&1 ; then
        echo $1
    else
        echo 0
    fi
}

function show_usage
{
    echo "$PRGNAME [-t seconds] [-d] [-m email-address] [-h] [-v]"
    echo "    Finding stale NFS mount points and show these + mail alert"
    echo "    Options: -t seconds (default is 10 seconds)"
    echo "             -d enable debugging"
    echo "             -m mail address"
    echo "             -h help"
    echo "             -v version"
    echo "    Comment: works also with a non-privileged user account"
}

function send_mail
{
    [[ -f "$LOGFILE" ]]  ||  LOGFILE=/dev/null
    expand "$LOGFILE" | mailx -s "$*" $mailusr
}

#####################################################################################
## MAIN
#####################################################################################

while getopts ":t:m:dhv" opt; do
    case $opt in
        d) DEBUG=1 ;;
        t) TSEC=$( is_num $OPTARG ) ; (( $TSEC == 0 )) && TSEC=10 ;;
        m) mailusr="$OPTARG" ;;
        h) show_usage; exit 0 ;;
        v) echo "$PRGNAME version $version"; exit 0  ;;
        :) echo "Missing argument" ; show_usage; exit 1 ;;
       \?) show_usage; exit 0 ;;
    esac
done

#MOUNTOPTS="-v"
STR="nfs"

cat /proc/mounts | grep -i "$STR" | while read exported_fs mount_point junk ;
 do
  #check_with_timeout $TSEC df $mount_point >/dev/null  || {
  timeout $TSEC df $mount_point >/dev/null  || {
    echo "stale $mount_point" | tee -a $LOGFILE 2>/dev/null
  }
 done

if [[ -f $LOGFILE ]] ; then
    grep -q "^stale" $LOGFILE && send_mail "$(hostname) - stale NFS mountpoint detected"
fi
