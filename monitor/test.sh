#!/bin/bash

DIR="/root"
HOSTNAME=$(hostname --fqdn)
INSTALL_DIR="$DIR/monitor-packages"
LOG_DIR="/var/log/monitor-packages"
LOG_FILE="$LOG_DIR/install.log"
ICINGA2_USER="nagios"
PLUGIN_DIR="/usr/lib/nagios/plugins"

# Install monitor-plugins
if [ ! -d "${PLUGIN_DIR}/thirdparty/monitor-plugins" ]; then
    echo "Installing monitor-plugins"
    cd ${PLUGIN_DIR}/thirdparty
    git clone https://monitor:glpat-Z7CzjGSea---yyGZG6Qs@tsd-repo.netnam.vn/monitoring/monitor-plugins.git

    # Ensure the sudoers.d directory exists
    if [ ! -d /etc/sudoers.d ]; then
        mkdir /etc/sudoers.d
        chmod 755 /etc/sudoers.d
    fi

    echo "${ICINGA2_USER} ALL=(root) NOPASSWD: ${PLUGIN_DIR}/thirdparty/monitor-plugins/plugin-update.sh" | EDITOR='tee -a' visudo -f /etc/sudoers.d/monitor-plugins
    echo "${ICINGA2_USER} ALL=(root) NOPASSWD: ${PLUGIN_DIR}/thirdparty/monitor-plugins/icinga2-validation.sh" | EDITOR='tee -a' visudo -f /etc/sudoers.d/icinga2
fi
