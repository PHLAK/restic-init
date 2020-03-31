#!/usr/bin/env bash
set -o errexit -o pipefail

echo "> Requesting root privileges"
if [[ $(sudo whoami) != "root" ]]; then
    echo "ERROR: This script requires root priveleges to run"
    exit 1
fi

## GLOBAL VARIABLES
########################################

RESTIC_BIN="/usr/local/bin/restic"
RESTIC_GROUP="restic"
RESTIC_CONFIG_DIRECTORY="/etc/restic"

## SCRIPT FUNCTIONS
########################################

function installResticBinary() {
    local ARCHIVE_URL="https://github.com/restic/restic/releases/download/v0.9.6/restic_0.9.6_linux_amd64.bz2"

    if [[ ! $(command -v restic) ]]; then
        echo -n "> Installing restic ... "
        curl --silent --location ${ARCHIVE_URL} | bzip2 --decompress \
            | sudo tee ${RESTIC_BIN} > /dev/null && sudo chmod +x  ${RESTIC_BIN}
        echo "DONE"
    else
        echo "> Restic already installed at $(command -v restic)"
    fi

    echo -n "> Checking for newer version ... "
    sudo restic self-update > /dev/null
    echo "DONE"
}

function installBashCompletion() {
    local BASH_COMPLETION_FILE="/etc/bash_completion.d/restic"

    if [[ -f ${BASH_COMPLETION_FILE} ]]; then
        while [[ ! ${OVERWRITE_BASH_COMPLETION_FILE} =~ [nyNY] ]]; do
            read -p "Bash completion file already exists, overwrite? [y|n]: " OVERWRITE_BASH_COMPLETION_FILE
        done

        if [[ ! ${OVERWRITE_BASH_COMPLETION_FILE} =~ [Yy] ]]; then
            echo "> Keeping previously created bash completion file ${BASH_COMPLETION_FILE}"
            return 0
        fi
    fi

    echo -n "> "
    sudo restic generate --bash-completion /etc/bash_completion.d/restic
}

function installManFiles() {
    echo -n "> "
    sudo restic generate --man /usr/share/man/man1/
}

function createResticGroup() {
    if [[ $(getent group ${RESTIC_GROUP}) ]]; then
        echo "> Group '${RESTIC_GROUP}' already exists"
        return 0
    fi

    sudo addgroup ${RESTIC_GROUP}
}

function configureRestic() {
    local CONFIG_FILE="${RESTIC_CONFIG_DIRECTORY}/config"

    if [[ ! -d ${RESTIC_CONFIG_DIRECTORY} ]]; then
        echo "> Creating restic config directory at ${RESTIC_CONFIG_DIRECTORY}"
        sudo mkdir ${RESTIC_CONFIG_DIRECTORY}
    fi

    echo "> Gathering configuration data from user"

    if [[ -f ${CONFIG_FILE} ]]; then
        while [[ ! ${OVERWRITE_CONFIG_FILE} =~ [nyNY] ]]; do
            read -p "Configuration file already exists, overwrite? [y|n]: " OVERWRITE_CONFIG_FILE
        done

        if [[ ! ${OVERWRITE_CONFIG_FILE} =~ [Yy] ]]; then
            echo "> Keeping previously created confuration file ${CONFIG_FILE}"
            return 0
        fi
    fi

    while [[ ! ${RESTIC_REPOSITORY} =~ [a-zA-Z_-]+ ]]; do
        read -p "Repository name: " RESTIC_REPOSITORY
    done

    echo "NOTE: Password must be at least 10 characters"
    while [[ ! ${RESTIC_PASSWORD} =~ .{10,} ]]; do
        read -s -p "Repository password: " RESTIC_PASSWORD; echo
    done


    if [[  ${RESTIC_REPOSITORY} =~ b2:[a-zA-Z_-]+ ]]; then
        while [[ ! ${B2_ACCOUNT_ID} =~ [0-9a-f]{25} ]]; do
            read -p "B2 Account ID: " B2_ACCOUNT_ID
        done

        while [[ ! ${B2_ACCOUNT_KEY} =~ .{31} ]]; do
            read -p "B2 Account Key: " B2_ACCOUNT_KEY
        done
    fi

    echo "> Gathering backup retention data from user"

    while [[ ! ${KEEP_HOURLY} =~ [0-9]+ ]]; do
        read -p "Hourly backups (default: 24): " KEEP_HOURLY
    done

    while [[ ! ${KEEP_DAILY} =~ [0-9]+ ]]; do
        read -p "Daily backups (default: 7): " KEEP_DAILY
    done

    while [[ ! ${KEEP_WEEKLY} =~ [0-9]+ ]]; do
        read -p "Weekly backups (default: 4): " KEEP_WEEKLY
    done

    while [[ ! ${KEEP_MONTHLY} =~ [0-9]+ ]]; do
        read -p "Monthly backups (default: 12): " KEEP_MONTHLY
    done

    while [[ ! ${KEEP_YEARLY} =~ [0-9]+ ]]; do
        read -p "Yearly backups (default: 1): " KEEP_YEARLY
    done

    echo -n "> Writing config file ${CONFIG_FILE} ... "
    cat resources/config \
        | sed "s|{{ RESTIC_BIN }}|${RESTIC_BIN}|" \
        | sed "s|{{ RESTIC_REPOSITORY }}|${RESTIC_REPOSITORY}|" \
        | sed "s|{{ RESTIC_PASSWORD }}|${RESTIC_PASSWORD}|" \
        | sed "s|{{ B2_ACCOUNT_ID }}|${B2_ACCOUNT_ID}|" \
        | sed "s|{{ B2_ACCOUNT_KEY }}|${B2_ACCOUNT_KEY}|" \
        | sed "s|{{ KEEP_HOURLY }}|${KEEP_HOURLY}|" \
        | sed "s|{{ KEEP_DAILY }}|${KEEP_DAILY}|" \
        | sed "s|{{ KEEP_WEEKLY }}|${KEEP_WEEKLY}|" \
        | sed "s|{{ KEEP_MONTHLY }}|${KEEP_MONTHLY}|" \
        | sed "s|{{ KEEP_YEARLY }}|${KEEP_YEARLY}|" \
        | sudo install --owner root --group ${RESTIC_GROUP} --mode u+rw,g+r /dev/stdin ${CONFIG_FILE}
    echo "DONE"
}

function installIncludesList() {
    local INCLUDES_LIST="${RESTIC_CONFIG_DIRECTORY}/includes.list"

    if [[ -f ${INCLUDES_LIST} ]]; then
        while [[ ! ${OVERWRITE_INCLUDES_LIST} =~ [nyNY] ]]; do
            read -p "Includes list already exists, overwrite? [y|n]: " OVERWRITE_INCLUDES_LIST
        done

        if [[ ! ${OVERWRITE_INCLUDES_LIST} =~ [Yy] ]]; then
            echo "> Keeping previously created includes list ${INCLUDES_LIST}"
            return 0
        fi
    fi

    echo -n "> Creating includes list at ${INCLUDES_LIST} ... "
    sudo install --owner root --group ${RESTIC_GROUP} --mode u+rw,g+r resources/includes.list ${INCLUDES_LIST}
    echo "DONE"
}

function installExcludesList() {
    local EXCLUDES_LIST="${RESTIC_CONFIG_DIRECTORY}/excludes.list"

    if [[ -f ${EXCLUDES_LIST} ]]; then
        while [[ ! ${OVERWRITE_EXCLUDES_LIST} =~ [nyNY] ]]; do
            read -p "Excludes list already exists, overwrite? [y|n]: " OVERWRITE_EXCLUDES_LIST
        done

        if [[ ! ${OVERWRITE_EXCLUDES_LIST} =~ [Yy] ]]; then
            echo "> Keeping previously created excludes list ${EXCLUDES_LIST}"
            return 0
        fi
    fi

    echo -n "> Creating excludes list at ${EXCLUDES_LIST} ... "
    sudo install --owner root --group ${RESTIC_GROUP} --mode u+rw,g+r resources/excludes.list ${EXCLUDES_LIST}
    echo "DONE"
}

function createCronJob() {
    local CRON_FILE="/etc/cron.hourly/restic-backup"

    if [[ -f ${CRON_FILE} ]]; then
        while [[ ! ${OVERWRITE_CRON_FILE} =~ [nyNY] ]]; do
            read -p "Cron file already exists, overwrite? [y|n]: " OVERWRITE_CRON_FILE
        done

        if [[ ! ${OVERWRITE_CRON_FILE} =~ [Yy] ]]; then
            echo "> Keeping previously created cron file ${CRON_FILE}"
            return 0
        fi
    fi

    echo -n "> Creating hourly cronjob at ${CRON_FILE} ... "
    sudo install --owner root --group ${RESTIC_GROUP} --mode u+rw,g+rx,o+x resources/restic-backup ${CRON_FILE}
    echo "DONE"
}

## MAIN
########################################

installResticBinary \
    && installBashCompletion \
    && installManFiles \
    && createResticGroup \
    && configureRestic \
    && installIncludesList \
    && installExcludesList \
    && createCronJob
