#!/bin/bash
# $Revision: 1.3 $
# $Date: 2015/11/06 10:37:48 $
# ----------------------------------------------------------------------------

shopt -s extglob

typeset -r platform=$(uname -s)                         # Platform
# sanity check to avoid issues with "hostname -s" command for lhost variable
[[ "$platform" != "Linux" ]] && _error "$PRGNAME is designed for Linux only"

typeset -x PRGNAME=${0##*/}                             # This script short name
typeset -x PRGDIR=${0%/*}                               # This script directory name
typeset -x PATH=$PATH:/sbin:/usr/sbin                   # Setting up rudimentary path
typeset -r dlog=/var/adm/log                            # Log directory
typeset instlog=$dlog/${PRGNAME%???}.scriptlog
typeset -r lhost=$(hostname -s)                         # short hostname
typeset -x BONDING="-"                                  # possible values=(F|H|N|-)
typeset -x hasip=""					# a flag to see if OS knows about ip cmd

declare -x -a slaves					# array of slave ethernet devices of a certain bond
declare -x -a bonds					# array of bonding ethernet devices
declare -x -a non_bonds					# array of non-bond (simple) ethernet devices

[[ $PRGDIR = /* ]] || PRGDIR=$(pwd) # Acquire absolute path to the script

# Integration tools know nothing about security and
# by default, anything they write is with 000 umask (big no, no)
umask 022


#################
### FUNCTIONS ###
#################

function show_ip_info {
    local interface="$1"
    local ip=$(LC_ALL=C ip addr show $interface scope global | grep inet | awk '{print $2}'  | tr '\n' ' ')
    local rt=$(LC_ALL=C ip route show dev $interface scope global | grep default | awk '{print $3}')
    [[ -z "$ip" ]] && return
    #LC_ALL=C ip -o link show dev $interface | grep -q ",UP" && status="UP"
    if ! $(check_device_down $interface); then
        status="UP"
    else
        status="DOWN"
    fi
    _print 22 "Interface:" "$interface [status: $status]" 
    _print 22 "  IP(s):"   "$ip"
    _print 22 "  Gateway:" "$rt"
}

function is_interface_redundant {
    local interface=${1}   # interface device
    local status=${2}      # string contains redundant status (Full, Half, None or "" [typically standalone device])
    local ip=$(LC_ALL=C ip addr show $interface scope global | grep inet | awk '{print $2}')

    [[ -z "$ip" ]] && return # only show interfaces with an IP address
    [[ -z "$status" ]] && {
        if ! check_device_down $interface; then
           status=UP
        else
           status=DOWN
        fi
    }

    case "$status" in
        N|None) # bonding is not-active or down
              _highlight 22 "Interface Health:" "Interface $interface is \"not redundant (DOWN)\""
              ;;
        H|Half) # bonding is only half active
              _highlight 22 "Interface Health:" "Interface $interface is \"not redundant\""
              ;;
        F|Full) # bonding is fully active
              _print 22 "Interface Health:" "Interface $interface is redundant"
              ;;
        U|UP)   # single interface is up
              _print 22 "Interface Health:" "Interface $interface is up"
              ;;
        D|DOWN) # single interface is most likely down
              _highlight 22 "Interface Health:" "Interface $interface is \"down\""
              ;;
    esac
    echo
}

function check_device_down {
    if LC_ALL=C ip -o link show dev $1 2>/dev/null | grep -q ",UP" ; then
       return 1
    else
       return 0
    fi
}

function _print_linux_os {
    if [[ -f /etc/system-release ]] ; then
        local str="$(cat /etc/system-release | head -1)"
    else
        local str="$(cat /etc/issue.net | head -1 | cut -d- -f1)"
    fi
    echo "$str" | grep -q "Welcome to" && {
         str=$(echo "$str" | cut -c12-)
    }
    echo "$str"
}

function HA_heartbeat {
    [[ ! -f /var/lib/heartbeat/hostcache ]] && return	# no HA heartbeat defined
    local str="$(awk '{print $1}' /var/lib/heartbeat/hostcache | cut -d. -f1 | tr '\n' ' ')"
    _print 22 "Heartbeat nodes:" "$str"
}

function HA_serviceguard {
    # on RH path is /usr/local/cmcluster; on SuSe path is /opt/cmcluster
    [ -d /usr/local/cmcluster/conf -o -d /opt/cmcluster/conf ] || return
    [[ -f /etc/cmcluster.conf ]] && . /etc/cmcluster.conf
    local str="$(awk '{print $1}' $SGCONF/cmclnodelist | cut -d. -f1 | sort -u | tr '\n' ' ')"
    _print 22 "Serviceguard nodes:" "$str"
}

function _echo {
    case $platform in
        Linux|Darwin) arg="-e " ;;
    esac

    echo $arg "$*"
} # echo is not the same between UNIX and Linux

function _note {
    _echo " ** $*"
} # Standard message display

function _highlight
{
    local i=$1
    i=$(_isnum $1)
    [[ $i -eq 0 ]] && i=22  # if i was 0, then make it 22 (our default value)
    printf "%${i}s %-80s " "$2" "$(tput smso)$3$(tput rmso)"
    echo
}

function _error {
    printf " *** ERROR: $* \n"
    exit 1
}

function _print {
   local i=$1
   i=$(_isnum $1)
   [[ $i -eq 0 ]] && i=22  # if i was 0, then make it 22 (our default value)
   printf "%${i}s %-80s " "$2" "$3"
   echo
}

function _line {
    typeset -i i
    while (( i < ${1:-80} )); do
        (( i+=1 ))
        _echo "-\c"
    done
    echo
} # draw a line

function _isnum
{
    #echo $(($1+0))         # returns 0 for non-numeric input, otherwise input=output
    if expr $1 + 0 >/dev/null 2>&1 ; then
        echo $1
    else
        echo 0
    fi
}

function _whoami {
   typeset wi
   case $platform in
       SunOS)
          typeset wi=/usr/ucb/whoami
          if [ -x $wi ]; then
              $wi
          else
              wi=$(id); wi=${wi%%\)*}; wi=${wi#*\(}
              echo $wi
          fi
          ;;
       *) whoami ;;
    esac
}

function _revision {
    typeset rev
    rev=$(awk '/Revision:/ { print $3 }' $PRGDIR/$PRGNAME | head -1)
    [ -n "$rev" ] || rev="UNKNOWN"
    echo $rev
} # Acquire revision number of the script and plug it into the log file

function _date_time {
    _note "$(date '+%Y-%b-%d %H:%M:%S')"
}

function _find_hwtype {
    typeset hwtype
    if /sbin/lspci 2>/dev/null | grep -q -i vmware; then  hwtype="Virtual VMware"; fi
    if /sbin/lspci 2>/dev/null |grep -q -i nvidia; then hwtype="Workstation (has nvidia)"; fi
    if /sbin/lspci 2>/dev/null |grep -q -i "RAID.*Hewlett-Packard"; then hwtype="HP Proliant"; fi
    if [[ -z "$hwtype" ]]; then
        if [[ -x /usr/sbin/dmidecode ]]; then
            hwtype=$(/usr/sbin/dmidecode | grep "Product Name"| head -1|cut -d: -f2-)
        else
            hwtype="unknown"
        fi
    fi
    echo $hwtype
}

function IsInArray {
    # return wether $1 equals one of the remaining arguments
    local needle="$1"
    while shift; do
       [[ "$needle" == "$1" ]] && return 0
    done
    return 1
}

function _find_eth_dev_via_sys {
    # digging into what we have of network interfaces:
    interfaces=$(cd /sys/class/net; echo !(bonding_masters))

    # get info on bonding interfaces:
    for interface in $interfaces; do
      if [[ -d /sys/class/net/$interface/bonding ]]; then
        bonds="$bonds $interface"
        for slave in $(</sys/class/net/$interface/bonding/slaves); do
          slaves="$slaves $slave"
        done
      fi
    done
    # get info on interfaces (bond or non-bond)
    for interface in $interfaces; do
       if [[ ! -d /sys/class/net/$interface/bonding ]]; then
         slave=0
         for s in $slaves; do
           [[ "$s" == "$interface" ]] && slave=1
         done
         [[ $slave == 0 ]] && non_bonds="$non_bonds $interface"
       fi
    done
}

function _find_eth_dev_via_proc {
    interfaces="$(cat /proc/net/dev | grep ':' | cut -d: -f1 | tr '\n' ' ')"

    # get info on bonding interfaces:
    for interface in $interfaces; do
      if [[ -f /proc/net/bonding/$interface ]]; then
        bonds="${bonds[@]} $interface"
        for slave in $(cat /proc/net/bonding/$interface | grep -i "^Slave Interface"  | cut -d: -f2); do
          slaves="${slaves[@]} $slave"
        done
      fi
    done
    # get info on interfaces (bond or non-bond)
    for interface in $interfaces; do
      if [[ ! -f /proc/net/bonding/$interface ]]; then
         ! IsInArray "$interface" $(trim "${slaves[@]}")  &&  non_bonds="${non_bonds[@]} $interface"
      fi
    done
}

function trim {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "$var"
}

function _show_slave_interface {
    # argument is bond-interface
#    if [[ -d /sys/class/net ]]; then
#        echo $(</sys/class/net/$interface/bonding/slaves)
#    else
        cat /proc/net/bonding/$1 | grep -i "^Slave Interface"  | cut -d: -f2 | tr '\n' ' ' | sed 's/^ *//g'
#    fi
}

# -----------------------------------------------------------------------------
#                              Sanity Checks:
# -----------------------------------------------------------------------------
[[ "$(_whoami)" != "root" ]] && _error "$PRGNAME requires root priveleges"

for i in $dlog; do
    if [ ! -d $i ]; then
        _note "$PRGNAME ($LINENO): [$i] does not exist."
        _echo "     -- creating now: \c"

        mkdir -p $i && echo "[  OK  ]" || {
            echo "[FAILED]"
            _note "Could not create [$i]. Exiting now"
            exit 1
        }
    fi
done

###############
### M A I N ###
###############

{
_line
_print 22 "Script:" "$PRGNAME"
_print 22 "Revision:" "$(_revision)"
_print 22 "Host:" "$lhost"
_print 22 "Hardware Type:" "$(_find_hwtype)"
_print 22 "Linux OS:" "$(_print_linux_os)"
HA_heartbeat    # print info on HA SLES 10 heartbeat if available
HA_serviceguard # print info on HA RHEL serviveguard if available
_print 22 "User:" "$(_whoami)"
_print 22 "Date:" "$(date)"
_print 22 "Log:" "$instlog"
_line; echo


#[[ -d /sys/class/net  ]] && _find_eth_dev_via_sys || _find_eth_dev_via_proc
_find_eth_dev_via_proc

# show all the network interfaces we found so far
_print 3 "**" "System $lhost has the following network interfaces:"
_print 12 "bonds:"  "${bonds[@]}"
_print 12 "slaves:" "${slaves[@]}"
_print 12 "non_bonds:" "${non_bonds[@]}"
echo

# show the details of the interfaces with IP addresses
_note "System $lhost has the following \"active\" network interfaces:"
# go through the bonds
for interface in ${bonds[@]}; do
  _print 22 "Bond:" "$interface"
  _print 22 "  Slaves:" "$(_show_slave_interface $interface)"
  #_print 22 "  Slaves:" "$(</sys/class/net/$interface/bonding/slaves)"
  for bondinterface in $(_show_slave_interface $interface)
  do
      if ! check_device_down $bondinterface; then
           _print 22 "  Slave Interface:" "$bondinterface [UP]"
      else
           _print 22 "  Slave Interface:" "$bondinterface [DOWN]"
      fi     
  done
  cat /proc/net/bonding/$interface > /tmp/bonding.$interface 2>/dev/null
  _print 22 "  Bonding mode:" "$(grep "^Bonding Mode"  /tmp/bonding.$interface | cut -d: -f2- | sed 's/^ *//g')"
  linkfail=$(grep "Link Failure Count:" /tmp/bonding.$interface | awk ' {sum += $4 } END {print sum}')
  _print 22 "  Link Failure Count:" "$linkfail"
  miistat=$(grep "MII Status:" /tmp/bonding.$interface | grep "down" | wc -l | sed 's/^ *//g')
  case $miistat in
     0) BONDING="F" ; _print 22 "  Bonding Health:"  "fully active" ;;
     1) BONDING="H" ; _highlight 22 "  Bonding Health:" "partial active" ;;
     2) BONDING="N" ; _highlight 22 "  Bonding Health:" "failed" ;;
     *) BONDING="N" ; _highlight 22 "  Bonding Health:" "failed" ;;
  esac
  
  _print 22 "  Mii mode:" "$(grep "^MII Polling Interval" /tmp/bonding.$interface | cut -d: -f2- | sed 's/^ *//g')ms"
  show_ip_info $interface

  # print message about bonding network being redundant or not
  is_interface_redundant $interface "$BONDING"
done

# go through the non-bonds
for interface in $non_bonds; do
  #echo "Interface: " $interface
  show_ip_info $interface
  is_interface_redundant $interface
done

}  | tee $instlog

# cleanup
rm -f /tmp/bonding.*

# ----------------------------------------------------------------------------
