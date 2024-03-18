#! /bin/bash

SEND_IP_CIDR="$1"
#SEND_PORT=$2
RCV_IP_CIDR="$2"
#RCV_PORT=$4


pushd ../dpdk/build/examples || ( echo "pushd ../dpdk/build/examples failed: $?"; exit 1)
echo "R $SEND_IP_CIDR 2" | tee rules_v4
echo "R $RCV_IP_CIDR 3" | tee -a rules_v4
echo "" | tee rules_v6 #try an empty file
#echo "R $6 $4" | tee -a rules_v6