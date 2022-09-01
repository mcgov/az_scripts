#! /bin/bash

# check for failover sriov pairing to detect if accelnet is up in az vm
# runs for 10 minutes
# author: Matthew G. McGovern mamcgove @ microsoft dotcom

NONVIRTUAL_NETDEV=$(ls /sys/class/net/ | grep -v `ls /sys/devices/virtual/net/`)
DEVICE_PAIRS=""
for i in 0 .. 30 ; do
    for upper in $NONVIRTUAL_NETDEV; do
        if [ -e /sys/class/net/$upper/lower_*/ ];
        then
            echo "found upper (failover) $upper"
            for lower in $NONVIRTUAL_NETDEV; do
                if [ -e /sys/class/net/$upper/lower_$lower/ ];
                then
                    echo "Found lower $lower paired to $upper."
                    LOWER_UP=`ip link show $lower up`
                    if [ -n "$LOWER_UP" ];
                    then
                        echo "Lower interface is up!"
                        exit 0;
                    else
                        echo "Warning: $lower was not reported as 'up' by ip"
                    fi
                fi
            done
        fi;
    done
    sleep 20s
done;

echo "No accelerated networking pair found up after 10m!"
exit 1
