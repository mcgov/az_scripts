#! /bin/bash

# get_timed_jobs.sh 
#     check for timed jobs on the machine

echo "SYSTEMD TIMERS:____________________________"
sudo systemctl status *timer --no-pager

# check systemd task time usage
echo "SYSTEMD ANALYZE BLAME:_____________________"
sudo systemd-analyze blame --no-pager

# get very verbose information about systemd tasks
echo "SYSTEMD ANALYZE DUMP:______________________"
sudo systemd-analyze dump --no-pager

# attempt get crontabs for all users (likely none is using systemd)
echo "ALL CRONTABS:______________________________"
getent passwd | cut -d: -f1 | xargs -I % sh -c 'sudo crontab -l -u %'

# check for any jobs scheduled using 'at' command if it's installed
echo "ANY ATQ?:__________________________________"
if [[ -n `command -v at` ]]; then
  sudo atq
fi
