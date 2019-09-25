#!/bin/bash

# Usage:
# wget https://cpa.st/setup/d9n.sh
# bash d9n.sh <hostname.com>

# Hostname and IP
# Hostname
if [ -z "$1" ]; then
	HOSTNAME=`hostname -f`
else
	HOSTNAME="$1"
	hostnamectl set-hostname $HOSTNAME
fi

# Prepare futher configuration
cd /root
WWWPASS=`shuf -zer -n20 {A..Z} {a..z} {0..9} | tr -d "\r\n\0"`
SQLPASS=`shuf -zer -n20 {A..Z} {a..z} {0..9} | tr -d "\r\n\0"`
CPAPASS=`shuf -zer -n20 {A..Z} {a..z} {0..9} | tr -d "\r\n\0"`
CPSPASS=`shuf -zer -n32 {A..Z} {a..z} {0..9} | tr -d "\r\n\0"`
COOKIES=`shuf -zer -n32 {A..Z} {a..z} {0..9} | tr -d "\r\n\0"`

# Make the result configuration file
echo "FTP" > config.txt
echo "" >> config.txt
echo "Address: sftp://$PUBLICIP:22" >> config.txt
echo "Login: wsvr" >> config.txt
echo "Password: $WWWPASS" >> config.txt
echo "Link: sftp://wsvr:$WWWPASS@$PUBLICIP:22" >> config.txt
echo "" >> config.txt
echo "MySQL" >> config.txt
echo "" >> config.txt
echo "Address: https://pms.$HOSTNAME/" >> config.txt
echo "Login: root" >> config.txt
echo "Password: $SQLPASS" >> config.txt
echo "" >> config.txt
echo "CPA database" >> config.txt
echo "" >> config.txt
echo "Database: cpa" >> config.txt
echo "Username: cpa" >> config.txt
echo "Password: $CPAPASS" >> config.txt

# Update system and install all the components
apt-get -y update
apt-get -y upgrade
apt-get -y install ca-certificates apt-transport-https
wget -q https://packages.sury.org/php/apt.gpg -O- | apt-key add -
echo "deb https://packages.sury.org/php/ stretch main" | tee /etc/apt/sources.list.d/php.list
apt-get -y update
apt-get -y upgrade
apt-get -y install coreutils mc logrotate nano net-tools memcached curl httrack mariadb-server zip unzip whois p7zip-full iotop iftop php7.3-fpm nginx
apt-get -y install php7.3-curl php7.3-gd php7.3-mysql php7.3-mbstring php7.3-xml php7.3-zip php7.3-soap php7.3-memcached

# Make necessary directories
mkdir -p /var/www
mkdir -p /var/www-data
mkdir -p /var/www-data/acme
mkdir -p /var/log/www
mkdir -p /var/log/www/$HOSTNAME
mkdir -p /var/log/www/pms.$HOSTNAME
mkdir -p /var/log/www/r.$HOSTNAME
mkdir -p /backup
mkdir -p /root/cert

# Create WWW user for FTP access
groupadd -g 1001 wsvr
useradd -g 1001 -u 1001 -d /var/www wsvr
echo -e "$WWWPASS\n$WWWPASS" | passwd wsvr

# Update MySQL settings
mysql -e "CREATE DATABASE cpa"
mysql -e "CREATE DATABASE phpmyadmin"
mysql -e "CREATE USER 'cpa'@'localhost' IDENTIFIED BY '$CPAPASS'"
mysql -e "GRANT ALL PRIVILEGES ON cpa.* TO 'cpa'@'localhost'"
mysql -e "UPDATE mysql.user SET Password = PASSWORD('$SQLPASS') WHERE User = 'root'"
mysql -e "UPDATE mysql.user SET Plugin = '' WHERE User = 'root'"
mysql -e "DROP USER ''@'localhost'"
mysql -e "DROP USER ''@'$(hostname)'"
mysql -e "DROP DATABASE test"
mysql -e "FLUSH PRIVILEGES"

# Setup PHP modules
phpdismod calendar
phpdismod ctype
phpdismod exif
phpdismod fileinfo
phpdismod ftp
phpdismod gettext
phpdismod phar
phpdismod pdo_mysql
phpdismod pdo
phpdismod readline
phpdismod shmop
phpdismod sysvmsg
phpdismod sysvsem
phpdismod sysvshm
phpdismod tokenizer
phpdismod wddx

# Load configuration archive
wget -q https://github.com/cosinus724/kjooo/raw/master/debian-cpast.zip
unzip -o -qq debian-cpast.zip -d /

# Change file permissions
chmod a+x /root/acme/dehydrated
chmod a+x /root/backup
chmod a+x /root/config
chmod a+x /root/rehost
chmod a+x /root/recert
chmod a+x /root/check-apache
chmod a+x /root/check-nginx
chmod a+x /root/webdav-sync

# Change change passwords in configuration files
sed -i "s/domain.ru/$HOSTNAME/g" /root/ssl-domains.txt
sed -i "s/domain.ru/$HOSTNAME/g" /root/config
sed -i "s/domain.ru/$HOSTNAME/g" /etc/nginx/conf.d/altercpa.conf
sed -i "s/SQLPASSWD/$SQLPASS/g" /root/config
sed -i "s/domain.ru/$HOSTNAME/g" /etc/zabbix/zabbix_agentd.conf
sed -i "s/SQLPASS/$SQLPASS/g" /etc/zabbix/zabbix_agentd.conf.d/userparameter_mysql.conf
sed -i "s/domain.ru/$HOSTNAME/g" /etc/php/7.3/mods-available/ioncube.ini
sed -i "s/domain.ru/$HOSTNAME/g" /var/www/default.site/go.php
sed -i "s/domain.ru/$HOSTNAME/g" /var/www/default.site/config.php
sed -i "s/sitecontrolkey/$CPSPASS/g" /var/www/default.site/config.php
sed -i "s/COOKIEAUTH/$COOKIES/g" /var/www/pms.domain.ru/config.inc.php
sed -i "s/SQLPASS/$SQLPASS/g" /var/www/pms.domain.ru/config.inc.php

# Setup additional modules
ln -s /etc/php/7.3/mods-available/ioncube.ini /etc/php/7.3/fpm/conf.d/0-ioncube.ini
ln -s /etc/php/7.3/mods-available/ioncube.ini /etc/php/7.3/cli/conf.d/0-ioncube.ini
mysql -u root -p"$SQLPASS" phpmyadmin < /var/www/pms.domain.ru/sql/create_tables.sql
rm -rf /var/www/html

# Download content
nohup openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048 &

# WWW directories
mkdir -p "/var/www/$HOSTNAME"
mv /var/www/pms.domain.ru "/var/www/pms.$HOSTNAME"
mv /var/www/default.site "/var/www/r.$HOSTNAME"
chown -R wsvr:wsvr /var/www
chown -R wsvr:wsvr /var/www-data

# Setup server and update certificates
service nginx restart
./recert
if [ -f "/root/cert/$HOSTNAME/fullchain.pem" ]; then
	sed -i "s/\#1//g" /etc/nginx/conf.d/altercpa.conf
fi
if [ -f "/root/cert/pms.$HOSTNAME/fullchain.pem" ]; then
	sed -i "s/\#2//g" /etc/nginx/conf.d/altercpa.conf
fi
if [ -f "/root/cert/r.$HOSTNAME/fullchain.pem" ]; then
	sed -i "s/\#3//g" /etc/nginx/conf.d/altercpa.conf
fi

# Restart all the services
service nginx restart
service php7.3-fpm restart
service mysql restart

# Root cron processor
echo "* * * * * bash /root/check-nginx >/dev/null 2>&1" > /var/spool/cron/crontabs/root
echo "0 5 * * * /root/backup >/dev/null 2>&1" >> /var/spool/cron/crontabs/root
echo "5 5 5 * * /root/acme/dehydrated --config /root/acme/config -c >/dev/null 2>&1" >> /var/spool/cron/crontabs/root
echo "6 5 5 * * /etc/init.d/nginx restart >/dev/null 2>&1" >> /var/spool/cron/crontabs/root
crontab /var/spool/cron/crontabs/root

# User cron processor
echo "* * * * * php -f /var/www/$HOSTNAME/tasks/1min.php >/dev/null 2>&1" > /var/spool/cron/crontabs/wsvr
echo "*/3 * * * * php -f /var/www/$HOSTNAME/tasks/3min.php >/dev/null 2>&1" >> /var/spool/cron/crontabs/wsvr
echo "*/10 * * * * php -f /var/www/$HOSTNAME/tasks/10min.php >/dev/null 2>&1" >> /var/spool/cron/crontabs/wsvr
echo "0 0 * * * php -f /var/www/$HOSTNAME/tasks/1day.php >/dev/null 2>&1" >> /var/spool/cron/crontabs/wsvr
echo "*/5 * * * * php -f /var/www/r.$HOSTNAME/cron.php >/dev/null 2>&1" >> /var/spool/cron/crontabs/wsvr
crontab -u wsvr /var/spool/cron/crontabs/wsvr
