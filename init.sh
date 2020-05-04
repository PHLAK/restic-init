#!/usr/bin/env bash
set -o errexit -o pipefail

## GLOBAL VARIABLES
########################################

RESTIC_BIN="/usr/local/bin/restic"
RESTIC_GROUP="restic"
RESTIC_CONFIG_DIRECTORY="/etc/restic"

## SCRIPT USAGE
########################################

function usage() {
	cat <<-EOF
		Usage: $(basename ${0}) [OPTIONS]

	    OPTIONS:

	        -h, --help             Print this help dialogue
	        -i, --install          Install the Restic binary
	        -b, --bash-completion  Install bash completion scripts
	        -m, --man-files        Install Restic man files
	        -l, --lists            Install includes and excludes lists
	        -g, --group            Create the "restic" group
	        -c, --configure        Run interactive configuration
	        -s, --services         Install systemd services and timers

	EOF
}

## SCRIPT FUNCTIONS
########################################

function requireRoot() {
    if [[ $(sudo whoami) != "root" ]]; then
        echo "ERROR: This action requires root priveleges to run"
        exit 1
    fi
}

function installResticBinary() {
    requireRoot

    if [[ ! $(command -v restic) ]]; then
        local RESTIC_VERSION="$(curl -s https://api.github.com/repos/restic/restic/releases/latest | jq --raw-output '.tag_name')"
        local ARCHIVE_URL="https://github.com/restic/restic/releases/download/${RESTIC_VERSION}/restic_${RESTIC_VERSION#v}_linux_amd64.bz2"

        echo -n "> Installing restic ... "
        curl --silent --location ${ARCHIVE_URL} | bzip2 --decompress \
            | sudo tee ${RESTIC_BIN} > /dev/null && sudo chmod +x  ${RESTIC_BIN}
        echo "DONE"

        return 0
    else
        echo "> Restic already installed at $(command -v restic)"
    fi

    echo -n "> Checking for newer version ... "
    sudo restic self-update > /dev/null
    echo "DONE"
}

function installBashCompletion() {
    requireRoot

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
    requireRoot

    local MAN_FILES_PATH="/usr/share/man/man1"

    if [[ $(compgen -G "${MAN_FILES_PATH}/restic*.1") ]]; then
        while [[ ! ${OVERWRITE_MAN_FILES} =~ [nyNY] ]]; do
            read -p "Some man files already exist, overwrite? [y|n]: " OVERWRITE_MAN_FILES
        done

        if [[ ! ${OVERWRITE_MAN_FILES} =~ [Yy] ]]; then
            echo "> Keeping previously created man files in ${MAN_FILES_PATH}"
            return 0
        else
            echo -n "> Removing existing man files ... "
            sudo rm ${MAN_FILES_PATH}/restic*.1
            echo "DONE"
        fi
    fi

    echo -n "> "
    sudo restic generate --man ${MAN_FILES_PATH}
}

function createResticGroup() {
    requireRoot

    if [[ $(getent group ${RESTIC_GROUP}) ]]; then
        echo "> Group '${RESTIC_GROUP}' already exists"
        return 0
    fi

    sudo addgroup ${RESTIC_GROUP}
}

function configureRestic() {
    requireRoot

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
    requireRoot

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
    requireRoot

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

function createServices() {
    requireRoot

    for FILE in resources/services/*.{service,timer}; do
        local DESTINATION="/etc/systemd/system/$(basename ${FILE})"

        if [[ -f ${DESTINATION} ]]; then
            while [[ ! ${OVERWRITE_FILE}  =~ [nyNY] ]]; do
                read -p "${DESTINATION} already exists, overwrite? [y|n]: " OVERWRITE_FILE
            done

            if [[ ! ${OVERWRITE_FILE} =~ [Yy] ]]; then
                echo "> Keeping previously created service file ${DESTINATION}"
                unset OVERWRITE_FILE
                continue
            fi
        fi

        echo -n "> Creating service file at ${DESTINATION} ... "
        sudo install --owner root --group root ${FILE} ${DESTINATION}
        unset OVERWRITE_FILE
        echo "DONE"
    done

    echo -n "> Reloading systemd daemon ... "
    sudo systemctl daemon-reload
    echo "DONE"

    while [[ ! ${ENABLE_TIMERS}  =~ [nyNY] ]]; do
        read -p "Enable backup timers? [y|n]: " ENABLE_TIMERS
    done

    if [[ ! ${ENABLE_TIMERS} =~ [Yy] ]]; then
        echo "> Timers not enabled"
        return 0
    fi

    echo -n "> "
    sudo systemctl enable --now restic-backup.timer
    
    echo -n "> "
    sudo systemctl enable --now restic-prune.timer
}

## OPTION / PARAMATER PARSING
########################################

eval set -- "$(getopt -n "${0}" -o hibmlgcs -l "help,install,bash-completion,man-files,lists,group,configure,services" -- "$@")"

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)            usage; exit ;;
        -i|--install)         installResticBinary; exit ;;
        -b|--bash-completion) installBashCompletion; exit ;;
        -m|--man-files)       installManFiles; exit ;;
        -l|--lists)           installIncludesList && installExcludesList; exit ;;
        -g|--group)           createResticGroup; exit ;;
        -c|--configure)       configureRestic; exit ;;
        -s|--services)        createServices; exit ;;
        --)                   shift; break ;;
    esac
done

## MAIN
########################################

installResticBinary \
    && installBashCompletion \
    && installManFiles \
    && createResticGroup \
    && configureRestic \
    && installIncludesList \
    && installExcludesList \
    && createServices
