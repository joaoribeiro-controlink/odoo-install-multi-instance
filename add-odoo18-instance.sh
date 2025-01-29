#!/bin/bash
################################################################################
# Script to create an Odoo 18 instance on Ubuntu 24.04 LTS
#-------------------------------------------------------------------------------
# This script creates a new Odoo 18 instance with its own virtual environment,
# instance directory, custom configuration, and Nginx configuration.
#-------------------------------------------------------------------------------
# Usage:
# 1. Save it as create_odoo_instance.sh
#    sudo nano create_odoo_instance.sh
# 2. Make the script executable:
#    sudo chmod +x create_odoo_instance.sh
# 3. Run the script:
#    sudo ./create_odoo_instance.sh
################################################################################

# Exit immediately if a command fails
set -e

# Function to generate a random password
generate_random_password() {
    openssl rand -base64 16
}

# Base variables
OE_USER="odoo"
OE_HOME="/odoo"
OE_BASE_CODE="${OE_HOME}"  # Directory where the base Odoo code is located
BASE_ODOO_PORT=8069
BASE_GEVENT_PORT=8072  # Base port for gevent (longpolling)
PYTHON_VERSION="3.11"

# Ensure the required version of Python is installed
if ! command -v python${PYTHON_VERSION} &> /dev/null; then
    echo "Python ${PYTHON_VERSION} is not installed. Installing Python ${PYTHON_VERSION}..."
    sudo apt update
    sudo apt install software-properties-common -y
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt update
    sudo apt install python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev -y
fi

# Check and install Certbot and Nginx if they are not installed
if ! command -v certbot &> /dev/null; then
    echo "Certbot is not installed. Installing Certbot..."
    sudo apt update
    sudo apt install certbot python3-certbot-nginx -y
fi

if ! command -v nginx &> /dev/null; then
    echo "Nginx is not installed. Installing Nginx..."
    sudo apt update
    sudo apt install nginx -y
    sudo systemctl enable nginx
    sudo systemctl start nginx
fi

# Get the server IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

# Function to find an available port
find_available_port() {
    local BASE_PORT=$1
    while true; do
        if lsof -i TCP:$BASE_PORT >/dev/null 2>&1; then
            BASE_PORT=$((BASE_PORT + 1))
        else
            echo "$BASE_PORT"
            break
        fi
    done
}

# Prompt for the instance name
read -p "Enter the name for the new instance (e.g., odoo1): " INSTANCE_NAME

# Validate the instance name
if [[ ! "$INSTANCE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Invalid instance name. Only letters, numbers, underscores, and dashes are allowed."
    exit 1
fi

# Prompt for the domain for the instance
read -p "Enter the domain for the instance (e.g., odoo.mycompany.com): " INSTANCE_DOMAIN

# Validate the domain name
if [[ ! "$INSTANCE_DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "Invalid domain name."
    exit 1
fi

# Ask if there is an Enterprise license
read -p "Do you have an Enterprise license for this instance? (yes/no): " ENTERPRISE_CHOICE
if [[ "$ENTERPRISE_CHOICE" =~ ^(yes|y)$ ]]; then
    HAS_ENTERPRISE="True"
else
    HAS_ENTERPRISE="False"
fi

# Ask if SSL should be enabled for this instance
read -p "Do you want to enable SSL with Certbot for the instance '$INSTANCE_NAME'? (yes/no): " SSL_CHOICE
if [[ "$SSL_CHOICE" =~ ^(yes|y)$ ]]; then
    ENABLE_SSL="True"
    # Prompt for email address for Certbot
    read -p "Enter your email address for Certbot: " ADMIN_EMAIL
    # Validate email address
    if ! [[ "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "Invalid email address."
        exit 1
    fi
else
    ENABLE_SSL="False"
fi

# Generate superadmin password
SUPERADMIN_PASS=$(generate_random_password)
echo "Superadmin password generated."

# Generate PostgreSQL password
DB_PASSWORD=$(generate_random_password)
echo "Database password generated."

# Create PostgreSQL user for the instance
sudo -u postgres psql -c "CREATE USER $INSTANCE_NAME WITH CREATEDB PASSWORD '$DB_PASSWORD';"
echo "PostgreSQL user '$INSTANCE_NAME' created."

# Create instance directory
INSTANCE_DIR="${OE_HOME}/${INSTANCE_NAME}"
sudo mkdir -p "${INSTANCE_DIR}"
sudo chown -R $OE_USER:$OE_USER "${INSTANCE_DIR}"

# Create custom addons directory
CUSTOM_ADDONS_DIR="${INSTANCE_DIR}/custom/addons"
sudo mkdir -p "${CUSTOM_ADDONS_DIR}"
sudo chown -R $OE_USER:$OE_USER "${CUSTOM_ADDONS_DIR}"

# If there is an Enterprise license, create Enterprise addons directory
if [ "$HAS_ENTERPRISE" = "True" ]; then
    ENTERPRISE_ADDONS_DIR="${INSTANCE_DIR}/enterprise/addons"
    sudo mkdir -p "${ENTERPRISE_ADDONS_DIR}"
    sudo chown -R $OE_USER:$OE_USER "${INSTANCE_DIR}/enterprise"
    echo "Enterprise addons directory created at '${ENTERPRISE_ADDONS_DIR}'."
    # Clone the Enterprise code into the Enterprise addons directory
    sudo -u $OE_USER -H git clone --depth 1 --branch master --single-branch https://www.github.com/odoo/enterprise "${ENTERPRISE_ADDONS_DIR}"
    echo "Enterprise code cloned into '${ENTERPRISE_ADDONS_DIR}'."
fi

# Create virtual environment for the instance
VENV_DIR="${INSTANCE_DIR}/venv"
sudo -u $OE_USER python${PYTHON_VERSION} -m venv "${VENV_DIR}"
echo "Virtual environment created at '${VENV_DIR}'."

# Upgrade pip in the virtual environment
sudo -u $OE_USER "${VENV_DIR}/bin/pip" install --upgrade pip

# Install wheel in the virtual environment
sudo -u $OE_USER "${VENV_DIR}/bin/pip" install wheel

# Install dependencies in the virtual environment
sudo -u $OE_USER "${VENV_DIR}/bin/pip" install -r "${OE_BASE_CODE}/requirements.txt"

# Install gevent in the virtual environment
sudo -u $OE_USER "${VENV_DIR}/bin/pip" install gevent

echo "Dependencies installed in the virtual environment."

# Find available ports
ODOO_PORT=$(find_available_port $BASE_ODOO_PORT)
GEVENT_PORT=$(find_available_port $BASE_GEVENT_PORT)

# Create Odoo configuration file
CONFIG_FILE="/etc/${OE_USER}-${INSTANCE_NAME}.conf"
sudo bash -c "cat > ${CONFIG_FILE}" <<EOF
[options]
admin_passwd = ${SUPERADMIN_PASS}
db_host = localhost
;list_db = False
db_user = ${INSTANCE_NAME}
db_password = ${DB_PASSWORD}
addons_path = ${OE_BASE_CODE}/addons,${CUSTOM_ADDONS_DIR}
http_port = ${ODOO_PORT}
gevent_port = ${GEVENT_PORT}
logfile = /var/log/${OE_USER}/${INSTANCE_NAME}.log
limit_memory_hard = 2677721600
limit_memory_soft = 1829145600
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
max_cron_threads = 1
workers = 2
EOF

# If there is an Enterprise license, add Enterprise addons path
if [ "$HAS_ENTERPRISE" = "True" ]; then
    sudo sed -i "s|addons_path = .*|&,$ENTERPRISE_ADDONS_DIR|" ${CONFIG_FILE}
fi

# If SSL is enabled, configure proxy_mode and dbfilter
if [ "$ENABLE_SSL" = "True" ]; then
    echo "proxy_mode = True" | sudo tee -a ${CONFIG_FILE}
    echo "dbfilter = ^%h\$" | sudo tee -a ${CONFIG_FILE}
fi

sudo chown $OE_USER:$OE_USER ${CONFIG_FILE}
sudo chmod 640 ${CONFIG_FILE}

echo "Configuration file created at '${CONFIG_FILE}'."

# Create logs directory
sudo mkdir -p /var/log/${OE_USER}
sudo chown ${OE_USER}:${OE_USER} /var/log/${OE_USER}

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/${OE_USER}-${INSTANCE_NAME}.service"
sudo bash -c "cat > ${SERVICE_FILE}" <<EOF
[Unit]
Description=Odoo18 - ${INSTANCE_NAME}
After=network.target

[Service]
Type=simple
User=${OE_USER}
Group=${OE_USER}
ExecStart=${VENV_DIR}/bin/python ${OE_BASE_CODE}/odoo-bin -c ${CONFIG_FILE}
WorkingDirectory=${OE_BASE_CODE}
StandardOutput=journal+console
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ${OE_USER}-${INSTANCE_NAME}.service
sudo systemctl start ${OE_USER}-${INSTANCE_NAME}.service

echo "Service '${OE_USER}-${INSTANCE_NAME}.service' created and started."

# Configure Nginx
NGINX_AVAILABLE="/etc/nginx/sites-available/${INSTANCE_DOMAIN}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${INSTANCE_DOMAIN}"

# Create minimal Nginx configuration
sudo bash -c "cat > ${NGINX_AVAILABLE}" <<EOF
# Odoo server
upstream odoo_${INSTANCE_NAME} {
    server 127.0.0.1:${ODOO_PORT};
}
upstream odoochat_${INSTANCE_NAME} {
    server 127.0.0.1:${GEVENT_PORT};
}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name ${INSTANCE_DOMAIN};

    access_log /var/log/nginx/${INSTANCE_NAME}.access.log;
    error_log /var/log/nginx/${INSTANCE_NAME}.error.log;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    # Add headers for Odoo proxy mode
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_redirect off;

    location / {
        proxy_pass http://odoo_${INSTANCE_NAME};
    }

    location /longpolling {
        proxy_pass http://odoochat_${INSTANCE_NAME};
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 90m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odoo_${INSTANCE_NAME};
    }
}
EOF

sudo ln -s ${NGINX_AVAILABLE} ${NGINX_ENABLED}
sudo nginx -t
sudo systemctl restart nginx

echo "Minimal Nginx configuration created."

# If SSL is enabled, obtain certificate and update configuration
if [ "$ENABLE_SSL" = "True" ]; then
    echo "Obtaining SSL certificate with Certbot..."
    sudo certbot certonly --nginx -d ${INSTANCE_DOMAIN} --non-interactive --agree-tos --email ${ADMIN_EMAIL}

    # Update Nginx configuration with SSL
    sudo bash -c "cat > ${NGINX_AVAILABLE}" <<EOF
# Odoo server
upstream odoo_${INSTANCE_NAME} {
    server 127.0.0.1:${ODOO_PORT};
}
upstream odoochat_${INSTANCE_NAME} {
    server 127.0.0.1:${GEVENT_PORT};
}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

# http -> https
server {
    listen 80;
    server_name ${INSTANCE_DOMAIN};
    rewrite ^(.*) https://\$host\$1 permanent;
}

server {
    listen 443 ssl;
    server_name ${INSTANCE_DOMAIN};
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    # SSL parameters
    ssl_certificate /etc/letsencrypt/live/${INSTANCE_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${INSTANCE_DOMAIN}/privkey.pem;
    ssl_session_timeout 30m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers off;

    # log
    access_log /var/log/nginx/${INSTANCE_NAME}.access.log;
    error_log /var/log/nginx/${INSTANCE_NAME}.error.log;

    # Redirect websocket requests to odoo gevent port
    location /websocket {
        proxy_pass http://odoochat_${INSTANCE_NAME};
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
        proxy_cookie_flags session_id samesite=lax secure;
    }

    # Redirect requests to odoo backend server
    location / {
        # Add Headers for odoo proxy mode
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;
        proxy_pass http://odoo_${INSTANCE_NAME};

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
        proxy_cookie_flags session_id samesite=lax secure;
    }

    # common gzip
    gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
    gzip on;
}
EOF

    sudo nginx -t
    sudo systemctl restart nginx
    echo "Nginx configuration updated with SSL."
fi

echo "-----------------------------------------------------------"
echo "The instance '$INSTANCE_NAME' has been successfully created!"
echo "-----------------------------------------------------------"
echo "Ports:"
echo "  Odoo Port (http_port): $ODOO_PORT"
echo "  Gevent Port (gevent_port): $GEVENT_PORT"
echo ""
echo "Service information:"
echo "  Service name: ${OE_USER}-${INSTANCE_NAME}.service"
echo "  Configuration file: ${CONFIG_FILE}"
echo "  Log file: /var/log/${OE_USER}/${INSTANCE_NAME}.log"
echo ""
echo "Custom addons folder: ${CUSTOM_ADDONS_DIR}"
if [ "$HAS_ENTERPRISE" = "True" ]; then
    echo "Enterprise addons folder: ${ENTERPRISE_ADDONS_DIR}"
fi
echo ""
echo "Database information:"
echo "  Database user: $INSTANCE_NAME"
echo "  Database password: $DB_PASSWORD"
echo ""
echo "Superadmin information:"
echo "  Superadmin password: $SUPERADMIN_PASS"
echo ""
echo "Manage the Odoo service with the following commands:"
echo "  Start:   sudo systemctl start ${OE_USER}-${INSTANCE_NAME}.service"
echo "  Stop:    sudo systemctl stop ${OE_USER}-${INSTANCE_NAME}.service"
echo "  Restart: sudo systemctl restart ${OE_USER}-${INSTANCE_NAME}.service"
echo ""
if [ "$ENABLE_SSL" = "True" ]; then
    echo "Nginx configuration file: ${NGINX_AVAILABLE}"
    echo "Access URL: https://${INSTANCE_DOMAIN}"
else
    echo "Nginx configuration file: ${NGINX_AVAILABLE}"
    echo "Access URL: http://${INSTANCE_DOMAIN}"
fi
echo "-----------------------------------------------------------"
