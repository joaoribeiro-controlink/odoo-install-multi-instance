#!/bin/bash
################################################################################
# Script to remove an Odoo 18 instance from the server
#-------------------------------------------------------------------------------
# This script allows you to select an existing Odoo 18 instance and deletes it
# completely, including:
# - PostgreSQL database and user
# - Systemd service
# - Odoo configuration
# - Instance directories and logs
# - Nginx configuration
#-------------------------------------------------------------------------------
# Usage:
# 1. Save it as remove-odoo-instance.sh
#    sudo nano remove-odoo-instance.sh
# 2. Make it executable:
#    sudo chmod +x remove-odoo-instance.sh
# 3. Run it:
#    sudo ./remove-odoo-instance.sh
################################################################################

# Exit on error
set -e

OE_USER="odoo"
OE_HOME="/odoo"
INSTANCE_CONFIG_PATH="/etc"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"

# Arrays to store existing instances
declare -a EXISTING_INSTANCES

# Function to terminate active connections to a PostgreSQL database
terminate_db_connections() {
    local DB_NAME=$1
    echo "* Terminating active connections to database \"$DB_NAME\""
    sudo -u postgres psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();"
}

# Gather existing instances
INSTANCE_CONFIG_FILES=(${INSTANCE_CONFIG_PATH}/${OE_USER}-*.conf)
if [ -f "${INSTANCE_CONFIG_FILES[0]}" ]; then
    for CONFIG_FILE in "${INSTANCE_CONFIG_FILES[@]}"; do
        INSTANCE_NAME=$(basename "$CONFIG_FILE" | sed "s/${OE_USER}-//" | sed 's/\.conf//')
        EXISTING_INSTANCES+=("$INSTANCE_NAME")
    done
else
    echo "No existing Odoo instances found."
    exit 1
fi

# Display the list of instances to the user
echo "Available Odoo instances:"
for i in "${!EXISTING_INSTANCES[@]}"; do
    echo "$i) ${EXISTING_INSTANCES[$i]}"
done

# Prompt the user to select an instance to delete
read -p "Enter the number of the instance you want to delete: " INSTANCE_INDEX
INSTANCE_NAME="${EXISTING_INSTANCES[$INSTANCE_INDEX]}"

if [[ -z "$INSTANCE_NAME" ]]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

# Confirmation
read -p "Are you sure you want to delete the instance '$INSTANCE_NAME'? This action cannot be undone. (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Operation canceled."
    exit 1
fi

# Define paths
OE_CONFIG="${OE_USER}-${INSTANCE_NAME}"
DB_USER=$INSTANCE_NAME
INSTANCE_DIR="${OE_HOME}/${INSTANCE_NAME}"
CONFIG_FILE="${INSTANCE_CONFIG_PATH}/${OE_CONFIG}.conf"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${OE_CONFIG}.service"
LOG_FILE="/var/log/${OE_USER}/${INSTANCE_NAME}.log"
NGINX_CONF_FILE="${NGINX_AVAILABLE}/${INSTANCE_NAME}"

echo "Deleting Odoo instance '$INSTANCE_NAME'..."

# Stop and disable the systemd service
if systemctl list-units --full -all | grep -q "${OE_CONFIG}.service"; then
    echo "* Stopping and disabling the Odoo service for $INSTANCE_NAME"
    sudo systemctl stop ${OE_CONFIG}.service
    sudo systemctl disable ${OE_CONFIG}.service
fi

# Remove the systemd service file
if [ -f "$SYSTEMD_SERVICE_FILE" ]; then
    echo "* Removing the systemd service file"
    sudo rm -f "$SYSTEMD_SERVICE_FILE"
    sudo systemctl daemon-reload
fi

# Remove PostgreSQL database and user
echo "* Dropping all databases owned by the PostgreSQL user '$DB_USER'"

# Fetch all databases owned by the user
DBS=$(sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datdba = (SELECT oid FROM pg_roles WHERE rolname = '$DB_USER');")

for DB in $DBS; do
    DB=$(echo $DB | xargs)
    if [[ "$DB" == "postgres" ]]; then
        echo "* Skipping the default 'postgres' database."
        continue
    fi
    terminate_db_connections "$DB"
    echo "* Dropping database \"$DB\""
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$DB\";"
done

echo "* Dropping the PostgreSQL user"
sudo -u postgres psql -c "DROP USER IF EXISTS $DB_USER;"

# Remove the Odoo configuration file
if [ -f "$CONFIG_FILE" ]; then
    echo "* Removing the Odoo configuration file"
    sudo rm -f "$CONFIG_FILE"
fi

# Remove the instance directory
if [ -d "$INSTANCE_DIR" ]; then
    echo "* Removing the instance directory"
    sudo rm -rf "$INSTANCE_DIR"
fi

# Remove the log file
if [ -f "$LOG_FILE" ]; then
    echo "* Removing log file"
    sudo rm -f "$LOG_FILE"
fi

# Remove the Nginx configuration if it exists
if [ -f "$NGINX_CONF_FILE" ]; then
    echo "* Removing Nginx configuration"
    sudo rm -f "$NGINX_CONF_FILE"
    sudo rm -f "${NGINX_ENABLED}/${INSTANCE_NAME}"
    sudo systemctl reload nginx
fi

echo "-----------------------------------------------------------"
echo "Instance '$INSTANCE_NAME' has been successfully deleted!"
echo "-----------------------------------------------------------"
