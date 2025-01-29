#!/bin/bash

# Odoo 18 installation script on Ubuntu 24.04 LTS

# Exit immediately if a command fails
set -e

# Prompt for the password for the PostgreSQL user
read -s -p "Enter the password for the PostgreSQL user 'odoo': " DB_PASSWORD
echo

echo "Updating the server..."
sudo apt-get update
sudo apt-get upgrade -y

echo "Installing and configuring security measures..."
sudo apt-get install -y openssh-server fail2ban
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

echo "Installing required packages and libraries..."
sudo apt-get install -y python3-pip python3-dev libxml2-dev libxslt1-dev zlib1g-dev \
libsasl2-dev libldap2-dev build-essential libssl-dev libffi-dev libjpeg-dev libpq-dev \
liblcms2-dev libblas-dev libatlas-base-dev npm node-less git python3-venv

echo "Installing Node.js and NPM..."
sudo apt-get install -y nodejs npm

if [ ! -f /usr/bin/node ]; then
    echo "Creating symbolic link for node..."
    sudo ln -s /usr/bin/nodejs /usr/bin/node
fi

echo "Installing less and less-plugin-clean-css..."
sudo npm install -g less less-plugin-clean-css

echo "Installing PostgreSQL..."
sudo apt-get install -y postgresql

echo "Creating PostgreSQL user for Odoo..."
sudo -u postgres psql -c "CREATE USER odoo WITH CREATEDB SUPERUSER PASSWORD '$DB_PASSWORD';"

echo "Creating system user for Odoo..."
sudo adduser --system --home=/odoo --group odoo18

echo "Cloning Odoo 18 from GitHub..."
sudo -u odoo18 -H git clone --depth 1 --branch master --single-branch https://www.github.com/odoo/odoo /odoo/

echo "Creating Python virtual environment..."
sudo -u odoo18 -H python3 -m venv /odoo/venv

echo "Installing required Python packages..."
sudo -u odoo18 -H /odoo/venv/bin/pip install wheel
sudo -u odoo18 -H /odoo/venv/bin/pip install -r /odoo/requirements.txt

echo "Installing wkhtmltopdf..."
wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb
sudo dpkg -i libssl1.1_1.1.0g-2ubuntu4_amd64.deb
sudo apt-get update
sudo apt-get install -y \
    fontconfig \
    libxrender1 \
    libxext6 \
    libfreetype6 \
    libx11-6 \
    xfonts-75dpi \
    xfonts-base
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.bionic_amd64.deb
sudo dpkg -i wkhtmltox_0.12.6-1.bionic_amd64.deb
sudo chmod +x /usr/local/bin/wkhtmltopdf
sudo chmod +x /usr/local/bin/wkhtmltoimage
