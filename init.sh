#!/usr/bin/env bash
set -o errexit -o pipefail

## GLOBAL VARIABLES
########################################

RESTIC_BIN="/usr/local/bin/restic"
RESTIC_CACHE_DIR="/var/cache/restic"
RESTIC_CONFIG_DIRECTORY="/etc/restic"
RESTIC_CONFIG_FILE="${RESTIC_CONFIG_DIRECTORY}/config"

## COLOR VARIABLES
########################################

OUTPUT_INDICATOR="$(tput setaf 4)>>>$(tput sgr0)"

## SCRIPT USAGE
########################################

function usage() {
	cat <<-EOF
		Usage: $(basename ${0}) [OPTIONS]

	    OPTIONS:

	        -h, --help             Print this help dialogue
	        -c, --check-deps       Check the system for required dependencies
	        -i, --install          Install the Restic binary
	        -r, --repository       Initialize the Restic repository
	        -l, --lists            Install includes and excludes lists
	        -c, --configure        Run interactive configuration
	        -s, --services         Install systemd services and timers

	EOF
}

## SCRIPT FUNCTIONS
########################################

function checkForMissingDependencies() {
    local DEPENDENCIES=('bzip2' 'ca-certificates' 'curl' 'jq' 'sudo' 'systemd')
    local MISSING_DEPENDENCIES=()

    echo "${OUTPUT_INDICATOR} Checking for missing dependencies..."
    for DEPENDENCY in "${DEPENDENCIES[@]}"; do
        if ! pacman --query "${DEPENDENCY}" &> /dev/null; then
            MISSING_DEPENDENCIES+=(${DEPENDENCY})
        fi
    done

    if [[ ! -z ${MISSING_DEPENDENCIES[@]} ]]; then
        echo "ERROR: One or more dependencies were not found (${MISSING_DEPENDENCIES[@]})"
        exit 1
    fi

    echo "${OUTPUT_INDICATOR} All required dependencies found"
}

function requireRoot() {
    if [[ $(sudo whoami) != "root" ]]; then
        echo "ERROR: This action requires root priveleges to run"
        exit 1
    fi
}

function installResticBinary() {
    requireRoot

    if [[ ! $(command -v restic) ]]; then
        echo -n "${OUTPUT_INDICATOR} Installing restic ... "
        sudo pacman --sync --noconfirm restic > /dev/null
        echo "DONE"

        return 0
    else
        echo "${OUTPUT_INDICATOR} Restic already installed at $(command -v restic)"
    fi
}

function configureRestic() {
    requireRoot

    if [[ ! -d ${RESTIC_CACHE_DIR} ]]; then
        echo "${OUTPUT_INDICATOR} Creating restic cache directory at ${RESTIC_CACHE_DIR}"
        sudo mkdir ${RESTIC_CACHE_DIR}
    fi

    if [[ ! -d ${RESTIC_CONFIG_DIRECTORY} ]]; then
        echo "${OUTPUT_INDICATOR} Creating restic config directory at ${RESTIC_CONFIG_DIRECTORY}"
        sudo mkdir ${RESTIC_CONFIG_DIRECTORY}
    fi

    echo "${OUTPUT_INDICATOR} Gathering configuration data from user"

    if [[ -f ${RESTIC_CONFIG_FILE} ]]; then
        while [[ ! ${OVERWRITE_CONFIG_FILE} =~ [nyNY] ]]; do
            read -p "Configuration file already exists, overwrite? [y|n]: " OVERWRITE_CONFIG_FILE
        done

        if [[ ! ${OVERWRITE_CONFIG_FILE} =~ [Yy] ]]; then
            echo "${OUTPUT_INDICATOR} Keeping previously created confuration file ${RESTIC_CONFIG_FILE}"
            return 0
        fi
    fi

    while [[ ! ${RESTIC_REPOSITORY} =~ [a-zA-Z_-]+ ]]; do
        read -p "Repository: " RESTIC_REPOSITORY
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

    echo "${OUTPUT_INDICATOR} Gathering backup retention data from user"

    while [[ ! ${KEEP_LAST} =~ [0-9]+ ]]; do
        read -p "Latest backups: " KEEP_HOURLY
    done

    while [[ ! ${KEEP_HOURLY} =~ [0-9]+ ]]; do
        read -p "Hourly backups: " KEEP_HOURLY
    done

    while [[ ! ${KEEP_DAILY} =~ [0-9]+ ]]; do
        read -p "Daily backups: " KEEP_DAILY
    done

    while [[ ! ${KEEP_WEEKLY} =~ [0-9]+ ]]; do
        read -p "Weekly backups: " KEEP_WEEKLY
    done

    while [[ ! ${KEEP_MONTHLY} =~ [0-9]+ ]]; do
        read -p "Monthly backups: " KEEP_MONTHLY
    done

    while [[ ! ${KEEP_YEARLY} =~ [0-9]+ ]]; do
        read -p "Yearly backups: " KEEP_YEARLY
    done

    echo -n "${OUTPUT_INDICATOR} Writing config file ${RESTIC_CONFIG_FILE} ... "
    cat resources/config \
        | sed "s|{{ RESTIC_CACHE_DIR }}|${RESTIC_CACHE_DIR}|" \
        | sed "s|{{ RESTIC_REPOSITORY }}|${RESTIC_REPOSITORY}|" \
        | sed "s|{{ RESTIC_PASSWORD }}|${RESTIC_PASSWORD}|" \
        | sed "s|{{ B2_ACCOUNT_ID }}|${B2_ACCOUNT_ID}|" \
        | sed "s|{{ B2_ACCOUNT_KEY }}|${B2_ACCOUNT_KEY}|" \
        | sed "s|{{ KEEP_HOURLY }}|${KEEP_HOURLY}|" \
        | sed "s|{{ KEEP_DAILY }}|${KEEP_DAILY}|" \
        | sed "s|{{ KEEP_WEEKLY }}|${KEEP_WEEKLY}|" \
        | sed "s|{{ KEEP_MONTHLY }}|${KEEP_MONTHLY}|" \
        | sed "s|{{ KEEP_YEARLY }}|${KEEP_YEARLY}|" \
        | sudo install --owner root --group root --mode u+rw /dev/stdin ${RESTIC_CONFIG_FILE}
    echo "DONE"
}

function initializeRepository() {
    export $(sudo grep -v '^#' ${RESTIC_CONFIG_FILE} | xargs)

    if restic --no-cache --repo ${RESTIC_REPOSITORY} snapshots &> /dev/null; then
        echo "${OUTPUT_INDICATOR} Respository already intialized at ${RESTIC_REPOSITORY}"
        return 0
    fi

    while [[ ! ${INITIALIZE_REPO} =~ [nyNY]  ]]; do
        read -p "Repository is not initilized, initialize now? [y|n]: " INITIALIZE_REPO
    done

    if [[ ! ${INITIALIZE_REPO} =~ [Yy] ]]; then
        echo "${OUTPUT_INDICATOR} Skipping repository initilization"
        return 0
    fi

    echo -n "${OUTPUT_INDICATOR} Initializaing repository at ${RESTIC_REPOSITORY} ... "
    restic init --repo ${RESTIC_REPOSITORY} > /dev/null
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
            echo "${OUTPUT_INDICATOR} Keeping previously created includes list ${INCLUDES_LIST}"
            return 0
        fi
    fi

    echo -n "${OUTPUT_INDICATOR} Creating includes list at ${INCLUDES_LIST} ... "
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
            echo "${OUTPUT_INDICATOR} Keeping previously created excludes list ${EXCLUDES_LIST}"
            return 0
        fi
    fi

    echo -n "${OUTPUT_INDICATOR} Creating excludes list at ${EXCLUDES_LIST} ... "
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
                echo "${OUTPUT_INDICATOR} Keeping previously created service file ${DESTINATION}"
                unset OVERWRITE_FILE
                continue
            fi
        fi

        echo -n "${OUTPUT_INDICATOR} Creating service file at ${DESTINATION} ... "
        sudo install --owner root --group root ${FILE} ${DESTINATION}
        unset OVERWRITE_FILE
        echo "DONE"
    done

    echo -n "${OUTPUT_INDICATOR} Reloading systemd daemon ... "
    sudo systemctl daemon-reload
    echo "DONE"

    while [[ ! ${ENABLE_TIMERS}  =~ [nyNY] ]]; do
        read -p "Enable backup timers? [y|n]: " ENABLE_TIMERS
    done

    # Run first backup?

    if [[ ! ${ENABLE_TIMERS} =~ [Yy] ]]; then
        echo "${OUTPUT_INDICATOR} Timers not enabled"
        return 0
    fi

    echo -n "${OUTPUT_INDICATOR} "
    sudo systemctl enable --now restic-backup.timer

    echo -n "${OUTPUT_INDICATOR} "
    sudo systemctl enable --now restic-prune.timer
}

## OPTION / PARAMATER PARSING
########################################

eval set -- "$(getopt -n "${0}" -o hcirlcs -l "help,check-deps,install,repository,lists,configure,services" -- "$@")"

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)            usage; exit ;;
        -c|--check-deps)      checkForMissingDependencies; exit ;;
        -i|--install)         installResticBinary; exit ;;
        -r|--repository)      initializeRepository; exit ;;
        -l|--lists)           installIncludesList && installExcludesList; exit ;;
        -c|--configure)       configureRestic; exit ;;
        -s|--services)        createServices; exit ;;
        --)                   shift; break ;;
    esac
done

## MAIN
########################################

checkForMissingDependencies

installResticBinary \
    && configureRestic \
    && initializeRepository \
    && installIncludesList \
    && installExcludesList \
    && createServices
