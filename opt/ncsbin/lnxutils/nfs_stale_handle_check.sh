#!/bin/bash

# Purpose: a simple stale NFS monitor script which mails an alert (and send a message to /var/log/messages)
# Script has been modified to work only on Linux
# Author: Gratien D'haese
# License: GPL v3


PATH=/usr/xpg4/bin:/usr/bin:/bin:/usr/local/bin:/usr/sbin:/sbin:.
# PROGRAM="$0"
PRGNAME=$(basename $0)
TSEC=10		# default 10 seconds (overrule with -t option)
DEBUG=		# default off (set to "1" to enable debugging)
mailusr=root    # default destination
# LOGFILE="/var/tmp/${PRGNAME%.*}-$(date +%Y%m%d-%H:%M).log"
PIDFILE="/tmp/StaleNFS.$$"
version=2.2

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
	echo "stale $(cat $PIDFILE)" | mailx -s "$*" $mailusr
}

function exec_df
{
    local tsec=$1
    local mntpt=$2

    # When no stale NFS mountpoint detected we return immediately
    timeout $tsec df $mntpt >/dev/null && return

    # We seem to have a stale NFS mountpoint - to avoid false alerts we double check
    sleep 2
    timeout $tsec df $mntpt >/dev/null && return
    # we also detected a stale NFS mountpoint at 2th attempt (write to $PIDFILE)
    printf "$mntpt " >> $PIDFILE
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

cat /proc/mounts | grep -i "$STR" | \
    while read exported_fs mount_point junk ;
    do
        exec_df $TSEC $mount_point
    done

# When there a is $PIDFILE then we have a stale NFS mountpoint
if [[ -f $PIDFILE ]] ; then
    send_mail "$(hostname) - stale NFS mountpoint detected"
    logger -t StaleNFS "stale mountpoint(s) $(cat $PIDFILE)"
    rm -f $PIDFILE
fi
