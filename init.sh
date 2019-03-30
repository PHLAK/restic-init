#!/usr/bin/env bash
set -o errexit -o pipefail

# Request root priveleges
echo "> Requesting root privileges"

if [[ $(sudo whoami) != "root" ]]; then
    echo "ERROR: This script requires root priveleges to run"
    exit
fi

## SCRIPT FUNCTIONS
########################################

function installResticBinary() {
    local ARCHIVE_URL="https://github.com/restic/restic/releases/download/v0.9.4/restic_0.9.4_linux_amd64.bz2"

    echo -n "> Installing restic ... "

    if [[ ! $(command -v restic) ]]; then
        curl --silent --location ${ARCHIVE_URL} | bzip2 --decompress \
            | sudo tee /usr/bin/restic > /dev/null && sudo chmod +x /usr/bin/restic
    fi

    echo "DONE"
}

function installBashCompletion() {
    echo -n "> "
    sudo restic generate --bash-completion /etc/bash_completion.d/restic
}

function installManFiles() {
    echo -n "> "
    sudo restic generate --man /usr/share/man/man1/
}

function configureRestic() {
    # local CONFIG_FILE="/etc/restic/config"
    local CONFIG_FILE="/tmp/restic/config"
    local RESTIC_REPOSITORY
    local RESTIC_PASSWORD
    local B2_ACCOUNT_ID
    local B2_ACCOUNT_KEY

    if [[ -f ${CONFIG_FILE} ]]; then
        while [[ ! ${OVERWRITE_CONFIG_FILE} =~ [nyNY] ]]; do
            echo -n "Configuration file already exists, overwrite? [Y|N]: "
            read OVERWRITE_CONFIG_FILE
        done

        if [[ ! ${OVERWRITE_CONFIG_FILE} =~ [Yy] ]]; then
            echo "> Keeping previously created confuration file"
            return 0
        fi
    fi

    while [[ ! ${RESTIC_REPOSITORY} =~ [a-zA-Z_-]+ ]]; do
        echo -n "Repository name: "
        read RESTIC_REPOSITORY
    done

    while [[ ! ${RESTIC_PASSWORD} =~ .+ ]]; do
        echo -n "Repository password: "
        read -s RESTIC_PASSWORD
        echo
    done

    while [[ ! ${B2_ACCOUNT_ID} =~ [0-9a-f]{25} ]]; do
        echo -n "B2 Account ID: "
        read B2_ACCOUNT_ID
    done

    # K001uumlLait+YHbwTpXyp3W+dj3QFo
    while [[ ! ${B2_ACCOUNT_KEY} =~ .{30,} ]]; do
        echo -n "B2 Account Key: "
        read B2_ACCOUNT_KEY
    done

    echo -n "> Writing config file ... "
    echo "" > ${CONFIG_FILE}
    echo "export RESTIC_REPOSITORY=\"b2:${RESTIC_REPOSITORY}\"" >> ${CONFIG_FILE}
    echo "export RESTIC_PASSWORD=\"${RESTIC_PASSWORD}\"" >> ${CONFIG_FILE}
    echo "export B2_ACCOUNT_ID=\" ${B2_ACCOUNT_ID}\"" >> ${CONFIG_FILE}
    echo "export B2_ACCOUNT_KEY=\"${B2_ACCOUNT_KEY}\"" >> ${CONFIG_FILE}
    echo "DONE"
}

function createCronJob() {
    echo -n "> Creating hourly cronjob ... "
    echo "DONE"
}

## MAIN
########################################

installResticBinary \
    && installBashCompletion \
    && installManFiles \
    && configureRestic \
    && createCronJob
