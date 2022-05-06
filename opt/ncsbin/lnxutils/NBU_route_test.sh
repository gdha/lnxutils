#!/bin/bash
echo ""
echo "**NBU** Checking Route connectivity for domain server in bp.conf"
echo ""

backupinterfaceip=`cat /usr/openv/netbackup/bp.conf |grep -i "^REQUIRED_INTERFACE"|cut -f2 -d"=" |xargs  nslookup |grep -i "Address:"|grep -v "#"|cut -f2 -d" "`
backupinterface=`ip add list |grep -i $backupinterfaceip|awk '{print $7}'`
if [[ -z "$backupinterface" ]] ; then
   echo "No IP address allocated on backup interface"
   exit 1
fi

echo $backupinterface |grep -iE "eno|eth|ens" >/dev/null
if [ $? = 0 ]
then
backupinterface_1=$backupinterface
else
backupinterface_1=`ip add list |grep -i $backupinterfaceip|awk '{print $8}'`
fi

backupinterfacefqdn=`cat /usr/openv/netbackup/bp.conf |grep -i "REQUIRED_INTERFACE"|cut -f2 -d"="`
 cat /usr/openv/netbackup/bp.conf|grep -i "SERVER =" |cut -f2 -d"=" |while read i
 do
 backup_serverip=`nslookup $i  |grep -i "Address:"|grep -v "#"|cut -f2 -d" "`
 ping -I $backupinterface_1 $i -c2  >/dev/null
 if [ $? -eq 0 ]
 then
 echo -e "Backup server $i ($backup_serverip)connectivity via $backupinterface_1  - $backupinterfacefqdn   is \033[1;32mOK \033[m"
 else
 echo -e "Backup server $i  ($backup_serverip)connectivity via $backupinterface_1  - $backupinterfacefqdn is \033[1;31mNOK \033[m"
 fi
 done

 cat /usr/openv/netbackup/bp.conf|grep -i "EMMSERVER" |cut -f2 -d"=" |while read i
 do
 backup_serverip=`nslookup $i  |grep -i "Address:"|grep -v "#"|cut -f2 -d" "`
 ping -I $backupinterface_1 $i -c2  >/dev/null
 if [ $? -eq 0 ]
 then
 echo -e "EMMSERVER server $i ($backup_serverip)connectivity via $backupinterface_1  - $backupinterfacefqdn   is \033[1;32mOK \033[m"
 else
 echo -e "EMMSERVER server $i  ($backup_serverip)connectivity via $backupinterface_1  - $backupinterfacefqdn is \033[1;31mNOK \033[m"
 fi
 done

 cat /usr/openv/netbackup/bp.conf|grep -i "MEDIA_SERVER" |cut -f2 -d"=" |while read i
 do
 backup_serverip=`nslookup $i  |grep -i "Address:"|grep -v "#"|cut -f2 -d" "`
 ping -I $backupinterface_1 $i -c2  >/dev/null
 if [ $? -eq 0 ]
 then
 echo -e "MEDIA_SERVER server $i ($backup_serverip)connectivity via $backupinterface_1  - $backupinterfacefqdn   is \033[1;32mOK \033[m"
 else
 echo -e "MEDIA_SERVER server $i  ($backup_serverip)connectivity via $backupinterface_1  - $backupinterfacefqdn is \033[1;31mNOK \033[m"
 fi
 done

