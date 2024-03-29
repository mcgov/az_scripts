#! /bin/bash

# NOTE: the demo runbook is designed to be placed at the root directory of LISA
if [ -e "./lisa/.venv/bin/activate" ]; then
    source ./lisa/.venv/bin/activate
else
    echo "Initialized LISA repo was not found, run lisa-install-first-time.sh"
    exit 1;
fi
# fill in the blanks, replace values as needed
lisa -r demo-runbook.yml -d -v "subscription_id:______" -v "admin_private_key_file:____" -v "keep_environment:no" -v "vm_size:Standard_D8ds_v5" -v "test_case_name:perf_sockperf_latency_tcp_sriov_busy_poll"  -v "concurrency:1" -v "marketplace_image:canonical 0001-com-ubuntu-server-jammy 22_04-lts latest" -v "rg_name:____"
exit $?