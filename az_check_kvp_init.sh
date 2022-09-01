#! /bin/bash
# author: Matthew G. McGovern mamcgove @ microsoft dotcom

# NOTE: script requires access to dmesg (may need root)

# check we are in a hyper-v/azure environment
HV_ENV_CHECK=`lsmod | grep -F hv_vmbus`
if [ -z "$HV_ENV_CHECK" ]; then exit 0; fi

# check that KVP is finished initializing
for i in 0 .. 60;
do
    FOUND_INIT_LOG=`dmesg | grep -F "hv_utils: KVP IC version"`
    if [ -z $FOUND_INIT_LOG ]; then;
        echo "WARNING: KVP was not initialized! Waiting..."
    else
        exit 0;
    fi
    sleep 10s
done

echo "KVP did not finish initializing in 10m!"
exit 1