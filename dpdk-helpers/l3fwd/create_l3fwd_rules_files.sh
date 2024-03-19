#! /bin/bash

SEND_IP_CIDR="$1"
RCV_IP_CIDR="$2"
RULES_FILE="$3"
DPDK_PATH="$4"

EXAMPLE_PATH="$DPDK_PATH/build/examples"
pushd "$EXAMPLE_PATH" || ( echo "pushd $EXAMPLE_PATH failed: $?"; exit 1)
echo "R $SEND_IP_CIDR 2" | tee "$RULES_FILE"
echo "R $RCV_IP_CIDR 3" | tee -a "$RULES_FILE"
popd ||  ( echo "popd from $EXAMPLE_PATH failed: $?"; exit 1)
