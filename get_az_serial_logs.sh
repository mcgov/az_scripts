#! /bin/bash
# NOTE: az cli works on all platforms so the command at the end should work in any shell

if [[  "$#" -ne "3" ]];
then
    echo "usage: ./get_serial_logs.sh <subscription> <resource-group-name> <vm-name>"
    exit -1
else
    echo -e "Fetching boot logs for:\n"            \
        "subscription: $1\n"                       \
        "resource group: $2\n"                     \
        "vm-name: $3"
fi

az vm boot-diagnostics get-boot-log --subscription "$1" --resource-group "$2" --name "$3"
