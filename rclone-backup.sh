#!/bin/bash

##############################################################################
# An rclone backup script by Chris Tippett (c.tippett@gmail.com)
#
# Originally adapted from the great work by Jared Males (jaredmales@gmail.com)
# https://gist.github.com/jaredmales/2f732254bb10002fc0549fa9aa0abdd7
# 
# Copyright (C) 2020 Chris Tippett (c.tippett@gmail.com)
#
# This script is licensed under the terms of the MIT license.
# https://opensource.org/licenses/MIT
#
# Runs the 'rclone sync' command. Designed to be used as a cron job.
#
# 1) Backup source
#    Edit the $src variable below to point to a local directory or remote location.
#
# 2) Backup destination
#    Edit the $dest variable to point to a local or remote (see rclone docs).
# 
# 3) Excluding files and directories
#    Edit the $opt_exclude_file variable below to point to a file listing files and directories to exclude.
#    See: https://rclone.org/filtering/
#
#    Also, any directory can be excluded by adding an '.rclone-ignore' file to it without editing the exclude file.
#    This file can be empty.  You can edit the location of this file with the RCLONE_EXCLUDE_FILE environment variable.
# 
# 4) You can change the bandwidth limits by editing $opt_bwlimit, which includes a timetable facility.  
#    See: https://rclone.org/docs/#bwlimit-bandwidth-spec
#
# 5) Logs:
#    -- By default rclone will log its output to the '.rclone' sub-directory under either $src or $dest (depending
#       on the one that is local to your filesystem).
#    -- The log filename is `rclone-<remotename>.log`, this is rotated using savelog.
#    -- The output of this script (run by cron) is written to stdout. This can be redirected to a location of your
#       choosing from within crontab.
#
# 6) Example crontab
#     30 2 * * * rclone-backup.sh "/src" "/dest" > /dev/null 2>&1
#   
##############################################################################

### CONFIGURATION
#
# input arguments
src="${1}" # source
dest="${2}" # destination
args=${3:-} # additional args for rclone command

# optional
# log_path="/var/log/" # override default log with your own location

# other options - https://rclone.org/flags/
RCLONE_EXCLUDE_FILE="$(dirname "$0")/rclone-exclude" # read file exclusion patterns from file
RCLONE_EXCLUDE_IF_PRESENT=".rclone-ignore" # exclude directories if this filename is present
# RCLONE_BWLIMIT="08:00,2M 00:00,off" # 2MB/s bandwidth limit between 8am and midnight
# RCLONE_MIN_AGE=15m # skip sync for files created in the last 15 minutes
# RCLONE_TRANSFERS=4 # number of file transfers to run in parallel
# RCLONE_CHECKERS=8 # number of checkers to run in parallel
# RCLONE_DELETE_EXCLUDED=true # delete files on dest excluded from sync
# RCLONE_DRIVE_USE_TRASH=true # send all files to the trash when deleting files (Google Drive only)
# RCLONE_IGNORE_CASE=false # ignore case when pattern matching 


### FUNCTIONS
#
# hash/obfuscate string
function hash() { md5sum < /dev/stdin | cut -f1 -d " "; }

# humanize seconds - https://unix.stackexchange.com/a/27014
function displaytime {
    local T=$1
    local D=$((T/60/60/24))
    local H=$((T/60/60%24))
    local M=$((T/60%60))
    local S=$((T%60))
    (( $D > 0 )) && printf '%dd' $D
    (( $H > 0 )) && printf '%dh' $H
    (( $M > 0 )) && printf '%dm' $M
    printf '%ds' $S
}

# takes unix epoch date as input and displays difference in seconds
function display_time_difference() {
    local seconds_diff="$(( $(date +%s) - ${1} ))"
    echo "$(displaytime "${seconds_diff}")"
}

# we'll use these to differentiate between executions and ensure only one sync happens at a time
src_dest_id="$(echo "${src}${dest}" | hash)"
execution_id="$(echo "$(date +%s)${src_dest_id}" | hash)"
lockfile="/tmp/rclone-${src_dest_id}.lock"

# let's get some help keeping our output formatted consistently
function format_output() {
    local timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local message="$(</dev/stdin)"
    if [ -n "${message}" ]; then
        echo "${timestamp} | ${execution_id:0:7} | ${message}"
    fi
}


### VALIDATE
#
# check whether the path (local or remote) exists
function check_path() {
    rclone lsf "${1}" >/dev/null 2>&1 || (echo "warning: input path ($1) does not exist, script will exit" | format_output; exit 1)
}

check_path "${src}"
check_path "${dest}"


### LOGGING
#
# find somewhere local we can use for rclone's logging output
if [ -d "${src}" ]; then
    # src is local, dest is remote
    remote_name="$(echo "${dest}" | cut -d ":" -f1)"
    default_log_path="${src}/.rclone/"
elif [ -d "${dest}" ]; then
    # src is remote, dest is local
    remote_name="$(echo "${src}" | cut -d ":" -f1)"
    default_log_path="${dest}/.rclone/"
else
    remote_name="" # unknown remote
    default_log_path="/var/log/"
fi
log_file="${log_path:-$default_log_path}/rclone${remote_name:+-$remote_name}.log"
mkdir -p "$(dirname "${log_file}")"


### RUN TIME
#
# function to run if there's already an active process running
exit_on_lock() {
    echo "warning: another sync is already in progress, script will exit" | format_output
    exit 1
}

(
    # check if a lock file exists for this src/dest combo
    flock -n 9 || exit_on_lock

    # configure logging for linux machines (no log rotation on mac machines)
    savelog -C -n -c 3 "${log_file}" >/dev/null 2>&1
    # -C force cleanup of cycled logfiles
    # -n do not rotate empty files
    # -c save cycle versions of the logfile

    # it's syncing time!
    echo "starting rclone sync (${src} -> ${dest})" | format_output
    start_time="$(date +%s)"

    # main rclone command
    rclone sync "${src}" "${dest}/latest" --log-file "${log_file}" --exclude-if-present "${RCLONE_EXCLUDE_IF_PRESENT}" --exclude-from "${RCLONE_EXCLUDE_FILE}" --backup-dir "${dest}/$(date -u +"%Y-%m-%dT%H%M%SZ")" --delete-excluded --retries 1 --low-level-retries 2 ${args}

    cat ${log_file}

    # finato
    duration="$(display_time_difference "${start_time}")"
    echo "success: rclone sync complete! (took "$duration")" | format_output

) 9>"${lockfile}"
