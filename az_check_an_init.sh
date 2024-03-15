#! /bin/bash

# check for failover sriov pairing to detect if accelnet is up in az vm
# runs for 10 minutes
# author: Matthew G. McGovern mamcgove @ microsoft dotcom
VIRTUAL_NETDEV=$(ls /sys/devices/virtual/net/)
ALL_NETDEV=$(ls /sys/class/net)
NONVIRTUAL_NETDEV=$(echo "$ALL_NETDEV" | grep -v "$VIRTUAL_NETDEV")
DEVICE_PAIRS=""
for _i in 0 .. 30 ; do
    for upper in $NONVIRTUAL_NETDEV; do
        lowers=$(ls /sys/class/net/"$upper"/lower_*/ 2> /dev/null)
        lower_exists=$(echo "$lowers" | wc -l)
        if [ "$lower_exists" == "1" ] && [ -e "$lowers" ];
        then
            echo "found upper (failover) $upper"
            for lower in $NONVIRTUAL_NETDEV; do
                if [ -e /sys/class/net/"$upper"/lower_"$lower"/ ];
                then
                    echo "Found lower $lower paired to $upper."
                    LOWER_UP=$(ip link show "$lower" up)
                    if [ -n "$LOWER_UP" ];
                    then
                        echo "Lower interface is up!"
                    else
                        echo "Warning: $lower was not reported as 'up' by ip"
                    fi

                    if [ -z "$DEVICE_PAIRS" ]; then
                        DEVICE_PAIRS="$upper,$lower"
                    else
                        DEVICE_PAIRS="$upper,$lower $DEVICE_PAIRS"
                    fi
                    break;
                fi
            done
        fi;
    done
    sleep 20s
done;

if [ -z "$DEVICE_PAIRS" ]; then
    echo "No accelerated networking pair found up after 10m!"
    exit 1;
else
    echo "Accelerated working interface pairs found: $DEVICE_PAIRS"
    exit 0;
fi
