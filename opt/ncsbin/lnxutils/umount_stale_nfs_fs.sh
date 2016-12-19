#!/bin/bash

# Script name: umount_stale_nfs_fs.sh
# Purpose of this script is to force an umount of stale NFS mount points
# To detect stale NFS we are using another script nfs_stale_handle_check.sh
# Author: Gratien D'haese
# License: GPL v3

# $Id: umount_stale_nfs_fs.sh,v 1.1 2014/12/03 13:02:17 gdhaese1 Exp $

# general parameters
####################
Stale_nfs_script="/opt/ncsbin/lnxutils/nfs_stale_handle_check.sh"

PATH=/usr/xpg4/bin:/usr/bin:/usr/ucb:/bin:/usr/local/bin:/usr/sbin:/sbin:/opt/ncsbin/lnxutils:./bin
PROGRAM="$0"
PRGNAME=$(basename $0)
DEBUG=          # default off (set to "1" to enable debugging)
mailusr=        # default no destination
LOGFILE="/var/tmp/${PRGNAME%.*}-$(date +%Y%m%d-%H:%M).log"

#############
# functions #
#############

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
    echo "$PRGNAME [-d] [-m email-address] [-h] [-v]"
    echo "    Finding stale NFS mount points and un-mount these (+ mail results)"
    echo "    Options:" 
    echo "             -d enable debugging"
    echo "             -m mail address"
    echo "             -h help"
    echo "             -v version"
}

function send_mail
{
    [[ -f "$LOGFILE" ]]  ||  LOGFILE=/dev/null
    expand "$LOGFILE" | mailx -s "$*" $mailusr
}

function _whoami
{
    if [ "$(whoami)" != "root" ]; then
        echo "$(whoami) - You must be root to run this script $PRGNAME"
        exit 1
    fi
}

function umount_stale_nfs_on_hpux
{
    $Stale_nfs_script | while read LINE
    do
        echo "WARNING: Found " $LINE
        MntPt=$(echo $LINE | awk '{print $2}')
        echo "Running /usr/sbin/umount -f $MntPt"
        /usr/sbin/umount -f $MntPt
        mount -p | grep -i NFS | grep -q "$MntPt"
        if [[ $? -eq 0 ]]; then
            echo "NFS mount point $MntPt is still mounted - try again:"
            # running fuser will also hang
            # /usr/sbin/fuser -k "$MntPt"
            echo "Running /sbin/fs/vxfs/vxumount -o force $MntPt"
            /sbin/fs/vxfs/vxumount -o force "$MntPt"
        fi 
        mount -p | grep -i NFS | grep -q "$MntPt"
        if [[ $? -eq 0 ]]; then
            echo "ERROR: was not able to un-mount $MntPt"
        else
            echo "NFS mount point $MntPt was successfully un-mounted"
        fi
    done
}

function umount_stale_nfs_on_linux
{
    $Stale_nfs_script | while read LINE
    do
        echo "WARNING: Found " $LINE
        MntPt=$(echo $LINE | awk '{print $2}')
        echo "Running umount -f $MntPt"
        umount -f $MntPt
        mount -t nfs | grep -q "$MntPt"
        if [[ $? -eq 0 ]]; then
            echo "NFS mount point $MntPt is still mounted - try again:"
            echo "Running umount -l $MntPt"
            umount -l $MntPt
        fi
        mount -t nfs | grep -q "$MntPt"
        if [[ $? -eq 0 ]]; then
            echo "ERROR: was not able to un-mount $MntPt"
        else
            echo "NFS mount point $MntPt was successfully un-mounted"
        fi
    done
}

function umount_stale_nfs_on_sunos
{
    $Stale_nfs_script | while read LINE
    do
        echo "WARNING: Found " $LINE
        MntPt=$(echo $LINE | awk '{print $2}')
        echo "Running umount -f $MntPt"
        umount -f $MntPt
        mount -v | grep nfs | grep -q "$MntPt"
        if [[ $? -eq 0 ]]; then
            echo "NFS mount point $MntPt is still mounted - try again:"
            echo "Running umount -f $MntPt"
            umount -f $MntPt
        fi
        mount -v | grep nfs | grep -q "$MntPt"
        if [[ $? -eq 0 ]]; then
            echo "ERROR: was not able to un-mount $MntPt"
        else
            echo "NFS mount point $MntPt was successfully un-mounted"
        fi
    done
}

###############
### M A I N ###
###############

_whoami

while getopts ":m:dhv" opt; do
    case $opt in
        d) DEBUG=1 ;;
        m) mailusr="$OPTARG" ;;
        h) show_usage; exit 0 ;;
        v) echo "$PRGNAME version $(revision)"; exit 0  ;;
        :) echo "Missing argument" ; show_usage; exit 1 ;;
       \?) show_usage; exit 0 ;;
    esac
done

{
case $(uname -s) in
    HP-UX) umount_stale_nfs_on_hpux ;;
    Linux) umount_stale_nfs_on_linux ;;
    SunOS) umount_stale_nfs_on_sunos ;;
        *) echo "No idea what to do (please inform me)" ; exit 1 ;;
esac
} 2>&1 | tee $LOGFILE

if [[ ! -z "$mailusr" ]]; then
    if [[ ! -s "$LOGFILE" ]]; then
        # LOGFILE is empty = no stale NFS (or LOGFILE does not exist)
        echo "No stale NFS mount points detected (good news)" >> "$LOGFILE"
    fi
    send_mail "Results of $PRGNAME run [$(date '+%Y%m%d-%H%M')]"
fi
