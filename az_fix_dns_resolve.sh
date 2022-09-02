#! /bin/bash

# Example code for fix for wireserver issue on latest ubuntu 18.04 aks and base udev and systemd update.
# specifically: libsystemd and udev amd64 237-3ubuntu10.54
# https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1988119
# READ BEFORE USE:
#   This script restarts the systemd.resolved service. This action has the potential to remove
#   mess with custom DNS/DHCP configurations. It is recommended to test this script
#   without any extra arguments on a single node:
#                       sudo ./az_fix_dns_resolve.sh
#   Optionally you can mark the affected package with apt-mark to prevent update, this is not recommended unless absolutely neccesary.
#   An updated package is available in ubuntu proposed channels for systemd as of 8/31/2022
# 
# We recommend first pursuing the AKS published mitigation steps available at https://github.com/joaguas/aksdnsfallback
#  if they are not sufficient or it is desired to not restart the vm, then testing this script may be appropriate.

#check for affected version
SYSTEMD_VERSION_MATCH=`dpkg-query --showformat='${Version}' --show systemd | grep -F "237-3ubuntu10.54"`
if [ -n "$SYSTEMD_VERSION_MATCH" ]; 
    then
        echo "Systemd version id: $SYSTEMD_VERSION_MATCH. Applying fix..."
    else
        echo "Systemd version did not match 237-3ubuntu10.54, found $(dpkg-query --showformat='${Version}' --show systemd). Skipping fix."
        case $1 in
        mark-hold)
            apt-mark hold systemd;;
        *)
            echo "NOTE: Not marking systemd with apt-mark hold to prevent update to bad version 237-3ubuntu10.54";;
        esac;
        exit 0;
fi
RESOLVECONF=/etc/systemd/resolved.conf
# check fallback lines ignoring commented out ones
# if line does not contain wireserver ip, append to line
if [ -z "`cat $RESOLVECONF | grep -v ^\# | grep FallbackDNS`" ];
then
    echo "FallbackDNS=168.63.129.16" >> $RESOLVECONF
else
    LAST_FALLBACK_LINE=`cat $RESOLVECONF | grep -v ^\# | grep FallbackDNS | tail -1`
    if [ -n "`echo $LAST_FALLBACK_LINE | grep -vF '168.63.129.16'`" ]; #if wireserver ip  is not in last declared fallback
    then
        sed "s/$LAST_FALLBACK_LINE/$LAST_FALLBACK_LINE 168.63.129.16/" -i $RESOLVECONF
    fi
fi
if [ -n "`cat $RESOLVECONF | grep -v ^\# | grep 168.63.129.16`" ];
then
    systemctl restart systemd-resolved
fi
NAME_RESOLVED=`dig +short microsoft.com`
if [ -n "$NAME_RESOLVED" ]; then
    echo "Name resolution for microsoft.com is: $(dig +short microsoft.com | tail -1)"
else
    echo "The fix failed"
    exit -1;
fi

# WARNING: these options may cause your VM to lose connectivity and require a full restart.
# TEST FIRST AND USE WITH CAUTION

UNMANAGED_ETH0=`networkctl status eth0 --no-pager | grep unmanaged`

NETWORK_RESET_COMMAND="udevadm trigger -cadd -yeth0 && systemctl restart systemd-networkd"
if [ -n "$UNMANAGED_ETH0" ];
then
    echo "NOTE: Applying workaround rule to ensure eth0 is managed on restart"
    NETWORK_RESET_COMMAND="$NETWORK_RESET_COMMAND; echo 'SUBSYSTEM==\"net\", SUBSYSTEMS==\"vmbus\", DRIVERS==\"hv_netvsc\", ENV{ID_NET_DRIVER}=\"hv_netvsc\"' > /etc/udev/rules.d/99-azure-netvsc.rules"
fi

echo "WARNING: Resetting networkd, this may cause VM to lose connectivity!" 
nohup sh -c "$NETWORK_RESET_COMMAND"


# including a command example to run a base64 encode/decode to send the command to the guest using ssh+ip
# ssh user@X.X.X.X  "echo `cat ./az_fix_dns_resolve.sh | base64 -w 0` | base64 -d | sudo sh"
