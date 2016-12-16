#!/bin/ksh
# Script: show_locked_users.sh
# Purpose: to get an overview of all users locked with a given reason (if found)
# Author: Gratien D'haese
# License: GPLv3
# Date: June/November 2016

# Define generic variables
typeset -r platform=$(uname -s)                         # Platform
typeset -r model=$(uname -m)                            # Model
typeset -r HOSTNAME=$(uname -n)                         # hostname
typeset os=$(uname -r); os=${os#B.}                     # e.g. 11.31
typeset -x PATH=/usr/xpg4/bin:$PATH:/sbin:/usr/sbin:/usr/ucb
typeset -r VERSION="1.0"
typeset -x PRGNAME=${0##*/}                             # This script short name
typeset -r dlog=/var/adm/log                            # Log directory
typeset instlog=$dlog/${PRGNAME%???}.log                # Log file location
typeset mailusr="root"                                  # default mailing destination 

#############
# Functions #
#############

function helpMsg {
    cat <<eof
Usage: $PRGNAME [-m <mail1,mail2>] -vh
        -m: The mail recipients seperated by comma (default: root)
        -h: This help message.
        -v: Revision number of this script.

eof
}

function send_mail {
        [ -f "$instlog" ] || instlog=/dev/null
        expand $instlog | mailx -s "$*" $mailusr
} # Standard email

function show_locked_users_hpux 
{
   # check if we are in trusted mode or
   /usr/lbin/getprpw root >/dev/null 2>&1
   rc=$?
   case $rc in
      0) # success - system is using trused mode
         show_locked_users_hpux_with_tcb
         ;;
      1) # user not privileged
         echo "Sorry - you are not authorized to run $PRGNAME"
         exit 1
         ;;
      2) # incorrect usage
         ;;
      3) # cannot find the password file
         echo "Cannot find the password file"
         exit 1
         ;;
      4) # system is not trusted
         show_locked_users_hpux_with_passwd 
         ;;
   esac
}

function show_locked_users_hpux_with_tcb
{
/usr/bin/listusers > /var/tmp/listusers.txt.$$
for USER in $(/usr/bin/listusers | awk '{print $1}')
do
    lock_pos=$(/usr/lbin/getprpw -r -m lockout $USER)
    gecos=$(grep $USER /var/tmp/listusers.txt.$$ | awk '{print $2,$3,$4,$5}')
    #user_name=$(grep $USER /etc/passwd|awk -F: '{print $5}')
    #lockout        returns the reason for a lockout in a "bit" valued
    #string, where 0 = condition not present, 1 is
    #present.  The position, left to right represents:
    #1 past password lifetime
    #2 past last login time (inactive account)
    #3 past absolute account lifetime
    #4 exceeded unsuccessful login attempts
    #5 password required and a null password
    #6 admin lock
    #7 password is a *

    if [[ "$lock_pos" != "0000000" ]] ; then
        # analyse lock_pos in detail (see man getprpw)
        # E.g.: hpsmh (System Management Homepage ) 0100001
        message=""
        bit=0
        for i in 1 2 3 4 5 6 7
        do
            bit=$( echo $lock_pos | cut -c${i}-${i} )
            case $i in
                1) [[ $bit = 1 ]] && message="past password lifetime" ;;
                2) if [[ $bit = 1 ]] ; then
                       [[ ! -z "$message" ]] && message="${message};inactive account" || message="inactive account"
                   fi ;;
                3) if [[ $bit = 1 ]] ; then
                       [[ ! -z "$message" ]] && message="${message};past absolute account lifetime" || message="past absolute account lifetime"
                   fi ;;
                4) if [[ $bit = 1 ]] ; then
                       [[ ! -z "$message" ]] && message="${message};exceeded unsuccessful login attempts" || message="exceeded unsuccessful login attempts"
                   fi ;;
                5) if [[ $bit = 1 ]] ; then
                       [[ ! -z "$message" ]] && message="${message};password required and a null password" || message="password required and a null password"
                   fi ;;
                6) if [[ $bit = 1 ]] ; then
                       [[ ! -z "$message" ]] && message="${message};admin lock" || message="admin lock"
                   fi ;;
                7) if [[ $bit = 1 ]] ; then
                       [[ ! -z "$message" ]] && message="${message};password is a *" || message="password is a *"
                   fi ;;
            esac
        done
        echo "$USER (${gecos}): Account LOCKED because of '$message'"
    fi
done
rm -f /var/tmp/listusers.txt.$$
}

function show_locked_users_hpux_with_passwd {
    echo "Not yet implemented"

}

function show_locked_users_linux {
    getent passwd > /var/tmp/listusers.txt.$$
    # entries look like:
    # rpc:x:32:32:Rpcbind Daemon:/var/lib/rpcbind:/sbin/nologin

    # Centrify in use?
    adinfo 2>&1 | grep -q connected && AD=1 || AD=0

    for USER in $( awk -F: '{print $1}' /var/tmp/listusers.txt.$$ )
    do
       # passwd -S $USER   (works only well if the USER is a local user)
       grep -q "^${USER}:" /etc/passwd
       if [[ $? -eq 0 ]] ; then
           gecos=$( grep "^${USER}:" /etc/passwd | cut -d: -f 5 )
           gid=$( grep "^${USER}:" /etc/passwd | cut -d: -f 4 )
           # skip check for gid > 0 and gid < 100
           if [[ $gid -lt 1 ]] || [[ $gid -gt 99 ]] ; then
               passwd -S $USER | grep -q LK && echo "$USER (${gecos}): Account LOCKED"
           fi
       #elif [[ $AD -eq 1 ]] ; then
           # for centrify we need to work differently
           # We decided to skip this as Linux via AD is the same as Windows AD - no need to check
           #if [[ "$(adquery user --locked $USER)" = "true" ]] ; then
           #   gecos="$(adquery user --gecos $USER)"
           #   echo "$USER (${gecos}): Account LOCKED"
           #fi
       fi
    done
    rm -f /var/tmp/listusers.txt.$$
}

####################################################################################
# MAIN
####################################################################################
if [[ "$(whoami)" != "root" ]]; then
    echo "$(whoami) - You must be root to run this script $PRGNAME"
    exit 1
fi


while getopts ":m:vh" opt; do
    case "$opt" in
        m)    mailusr="$OPTARG"
              [[ -z "$mailusr" ]] && mailusr=root ;;
        h)    helpMsg; exit 0 ;;
        v)    echo "$PRGNAME version $VERSION"; exit 0 ;;
        \?)   echo "$PRGNAME: unknown option used: [$OPTARG]."
              helpMsg; exit 0 ;;
    esac
done
shift $(( OPTIND - 1 ))

[[ ! -d $dlog ]] && mkdir -m 755 -p $dlog

# before jumping into MAIN move the existing instlog to instlog.old
[[ -f $instlog ]] && mv -f $instlog ${instlog}.old

{
echo "               Script: $PRGNAME"
echo "             Revision: $VERSION"
echo "     Mail Destination: $mailusr"
echo "                 Date: $(date)"
echo "                  Log: $instlog"
echo

case "$platform" in
    HP-UX) show_locked_users_hpux ;;
    Linux) 
	   # see man pam_tally2
	   # e.g. pam_tally2 --user marketpl --reset
	   show_locked_users_linux
	   ;;
    *    ) echo "Have no procedure yet for platform $platform - please fill the gab"
	   exit 1 ;;
esac

} 2>&1 | tee -a $instlog 2>/dev/null # tee is used in case of interactive run
[ $? -eq 1 ] && exit 1          # do not send an e-mail as non-root (no log file either)

grep -q LOCKED $instlog && send_mail "Locked users on system $HOSTNAME"
exit 0
