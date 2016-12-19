#!/bin/bash

# Purpose: a simple stale NFS monitor script which mails an alert (for now)
# Author: Gratien D'haese
# License: GPL v3

# $Id: nfs_stale_handle_check.sh,v 1.6 2015/01/05 12:40:57 gdhaese1 Exp $

PATH=/usr/xpg4/bin:/usr/bin:/bin:/usr/local/bin:/usr/sbin:/sbin:.
PROGRAM="$0"
PRGNAME=$(basename $0)
TSEC=10		# default 10 seconds (overrule with -t option)
DEBUG=		# default off (set to "1" to enable debugging)
mailusr=root    # default destination
LOGFILE="/var/tmp/${PRGNAME%.*}-$(date +%Y%m%d-%H:%M).log"

function check_with_timeout
{
    [ "$DEBUG" ] && set -x
    TIMEOUT=$1
    shift
    COMMAND="$@"
    RET=0
    # Launch command in backgroup
    [ ! "$DEBUG" ] && exec 6>&2 # Link file descriptor #6 with stderr.
    [ ! "$DEBUG" ] && exec 2> /dev/null # Send stderr to null (avoid the Terminated messages)
    $COMMAND 2>&1 >/dev/null &
    COMMAND_PID=$!
    [ "$DEBUG" ] && echo "Background command pid $COMMAND_PID, parent pid $$"
    # Timer that will kill the command if times out
    ( sleep $TIMEOUT
      MY_CMD_PID=$(UNIX95= ps -p $COMMAND_PID -o pid,ppid | awk -v parent=$$ '$2==parent {print $1}')
      if [[ ! -z "$MY_CMD_PID" ]]; then
          kill "$MY_CMD_PID"
      fi
    ) &
    KILLER_PID=$!
    [ "$DEBUG" ] && echo "Killer command pid $KILLER_PID, parent pid $$"
    wait $COMMAND_PID
    RET=$?
    # Kill the killer timer
    [ "$DEBUG" ] && echo List process that will be killed
    [ "$DEBUG" ] && UNIX95= ps -p $KILLER_PID -o pid,ppid
    MY_PID=$(UNIX95= ps -p $KILLER_PID -o pid,ppid | awk -v parent=$$ '$2==parent {print $1}')
    if [[ ! -z "$MY_PID" ]]; then
        [ "$DEBUG" ] && echo "About to kill pid $MY_PID"
        kill "$MY_PID"
    fi
    [ ! "$DEBUG" ] && exec 2>&6 6>&- # Restore stderr and close file descriptor #6.
    return $RET
}

function is_num
{
    if expr $( echo $1 | cut -d. -f1 ) + 0 >/dev/null 2>&1 ; then
        echo $1
    else
        echo 0
    fi
}

function revision
{
    rev=$(grep "^#" $PROGRAM | grep "Id:"  | awk '{print $4}')
    echo $(is_num $rev)   # if non-numeric echo will display 0
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
        v) echo "$PRGNAME version $(revision)"; exit 0  ;;
        :) echo "Missing argument" ; show_usage; exit 1 ;;
       \?) show_usage; exit 0 ;;
    esac
done

if [[ "$(uname -r)" = "B.11.11" ]]; then
    echo "$PRGNAME does not work properly under HP-UX B.11.11!"
    echo "We prefer to exit now to prevent a blocking on NFS issue"
    exit 0
fi

case $(uname -s) in
    HP-UX) MOUNTOPTS="-p" ; STR="[nN][fF][sS]" ;;
    Linux) MOUNTOPTS="-t nfs" ; STR="[nN][fF][sS]" ;;
    SunOS) MOUNTOPTS="-p" ; STR="[nN][fF][sS]" ;;
esac

mount $MOUNTOPTS | grep "$STR" | while read exported_fs arg1 arg2 junk ;
 do
  case $(uname -s) in
    HP-UX) mount_point=$arg1 ;;  # dbciRPS.dfdev.jnj.com:/export/sapmnt/RPS   /sapmnt/RPS                   nfs
    Linux) mount_point=$arg2 ;;  # itsbebevcorp01.jnj.com:/vol/itsbebevcorp01_cfg2html/cfg2html/linux on /mnt type nfs 
    SunOS) mount_point=$arg2 ;;  # hpx189.ncsbe.eu.jnj.com:/test - /mnt nfs
  esac
  check_with_timeout $TSEC df $mount_point >/dev/null 
  rc=$?
  [[ $rc -ne 0 ]] && echo "stale $mount_point" | tee -a $LOGFILE 2>/dev/null
 done

if [[ -f $LOGFILE ]] ; then
    grep -q "^stale" $LOGFILE && send_mail "$(hostname) - stale NFS mountpoint detected"
fi
