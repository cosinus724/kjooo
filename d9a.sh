#!/bin/bash

# Usage:
# wget https://github.com/cosinus724/kjooo/raw/master/d9.zip
# bash d9a.sh <hostname.com>

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
COOKIES=`shuf -zer -n32 {A..Z} {a..z} {0..9} | tr -d "\r\n\0"`

# Make the result configuration file
echo "FTP" > config.txt
echo "" >> config.txt
echo "Address: sftp://$HOSTNAME:22" >> config.txt
echo "Login: wsvr" >> config.txt
echo "Password: $WWWPASS" >> config.txt
echo "Link: sftp://wsvr:$WWWPASS@$HOSTNAME:22" >> config.txt
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
apt-get -y install coreutils mc logrotate nano net-tools memcached curl httrack mysql-server apache2 php7.2 zip unzip whois p7zip-full iotop iftop
apt-get -y install php7.2-curl php7.2-gd php7.2-mysql php7.2-mbstring php7.2-xml php7.2-zip php7.2-soap php7.2-memcached

# Make necessary directories
mkdir -p /var/www
mkdir -p /var/www-data
mkdir -p /var/www-data/acme
mkdir -p /var/log/www
mkdir -p /var/log/www/default.site
mkdir -p /var/log/www/$HOSTNAME
mkdir -p /var/log/www/pms.$HOSTNAME
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

# Setup Apache modules
a2dismod -f access_compat
a2dismod -f auth_basic
a2dismod -f authn_core
a2dismod -f authn_file
a2dismod -f authz_host
a2dismod -f authz_user
a2dismod -f autoindex
a2dismod -f negotiation
a2dismod -f status
a2enmod ssl
a2enmod rewrite
a2enmod headers
a2enmod expires

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
wget -q https://github.com/cosinus724/kjooo/raw/master/d9.zip
unzip -o -qq d9.zip -d /

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
sed -i "s/domain.ru/$HOSTNAME/g" /etc/apache2/apache2.conf
sed -i "s/SQLPASSWD/$SQLPASS/g" /root/config
sed -i "s/domain.ru/$HOSTNAME/g" /etc/zabbix/zabbix_agentd.conf
sed -i "s/SQLPASS/$SQLPASS/g" /etc/zabbix/zabbix_agentd.conf.d/userparameter_mysql.conf
sed -i "s/domain.ru/$HOSTNAME/g" /var/www/default.site/go.php
sed -i "s/domain.ru/$HOSTNAME/g" /var/www/default.site/config.php
sed -i "s/COOKIEAUTH/$COOKIES/g" /var/www/pms.domain.ru/config.inc.php
sed -i "s/SQLPASS/$SQLPASS/g" /var/www/pms.domain.ru/config.inc.php

# Setup additional modules
mysql -u root -p"$SQLPASS" phpmyadmin < /var/www/pms.domain.ru/sql/create_tables.sql
rm -rf /var/www/html	

# WWW directories
mkdir -p "/var/www/$HOSTNAME"
mv /var/www/pms.domain.ru "/var/www/pms.$HOSTNAME"
chown -R wsvr:wsvr /var/www
chown -R wsvr:wsvr /var/www-data

# Setup server and update certificates
./rehost
./recert
./rehost
service apache2 restart
service mysql restart

# Root cron processor
echo "* * * * * bash /root/check-apache >/dev/null 2>&1" > /var/spool/cron/crontabs/root
echo "*/5 * * * * /root/rehost >/dev/null 2>&1" >> /var/spool/cron/crontabs/root
echo "0 5 * * * /root/backup >/dev/null 2>&1" >> /var/spool/cron/crontabs/root
echo "5 5 5 * * /root/acme/dehydrated --config /root/acme/config -c >/dev/null 2>&1" >> /var/spool/cron/crontabs/root
echo "6 5 5 * * /etc/init.d/apache2 restart >/dev/null 2>&1" >> /var/spool/cron/crontabs/root
crontab /var/spool/cron/crontabs/root

# User cron processor
echo "* * * * * php -f /var/www/$HOSTNAME/tasks/1min.php >/dev/null 2>&1" > /var/spool/cron/crontabs/wsvr
echo "*/3 * * * * php -f /var/www/$HOSTNAME/tasks/3min.php >/dev/null 2>&1" >> /var/spool/cron/crontabs/wsvr
echo "*/10 * * * * php -f /var/www/$HOSTNAME/tasks/10min.php >/dev/null 2>&1" >> /var/spool/cron/crontabs/wsvr
echo "0 0 * * * php -f /var/www/$HOSTNAME/tasks/1day.php >/dev/null 2>&1" >> /var/spool/cron/crontabs/wsvr
echo "*/5 * * * * php -f /var/www/default.site/cron.php >/dev/null 2>&1" >> /var/spool/cron/crontabs/wsvr
crontab -u wsvr /var/spool/cron/crontabs/wsvr
