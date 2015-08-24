#!/bin/bash

# Update home directories owner and group based on account's LDAP uid:gid.   Account_name=Home_dir
# Deb-based

if [ $(id -u) -ne 0 ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

force=0

while [[ $# > 0 ]]
do
key="$1"
shift
case $key in
    -f|--force)
    force=1
    shift
    ;;
    *)
            # unknown option
    ;;
esac
done

type ldapsearch 1>/dev/null 2>&1
ls_exist=$?	# is ldapsearch exists
if [ $ls_exist -ne 0 ] ; then 
	if [ $force -eq 1 ] ; then
		echo -en "Installing LDAP-UTILS. Please Wait..."
		apt-get install -y ldap-utils 1>/dev/null 2>&1
		status=$?
		if [ $status -eq 0 ] ; then echo "Done." ; else echo "Installation failed." ; exit 1 ; fi
	else
		echo "LDAP-UTILS not installed or not hashed. Aborted. Please install or use -f key." ; exit 1
	fi		
fi

cd /home
echo "Affected UIDs"

for uiddir in `ls -d */` ; do
        uid=$(echo $uiddir | sed 's/\/$//')
        uidnumber=$(ldapsearch -x -b dc=dbi "uid=${uid}" uidnumber -LLL | grep uidnumber | cut -d' ' -f2)
        printf 'uid: %-20s uidnumber: %-15s' $uid $uidnumber
#       echo -en "uid: $uid \t uidnumber: $uidnumber\t"
        if ! [[ $uidnumber =~ ^[0-9]+$ ]] ; then echo "not found in LDAP or no UID assigned" ; continue ; fi
        chown -R --silent "$uidnumber:$uidnumber" "${uid}/"
        status=$?
        if [ $status -ne 0 ] ; then echo "error" ; else echo "updated" ; fi
done

