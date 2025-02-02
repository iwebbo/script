#!/bin/bash -xe

# Pré-requis
# sudo aptitude install apache2 libapache2-mod-php5 php5-mysql php5-gd mysql-server
# sudo a2enmod rewrite
# sudo echo "127.0.0.1       www.alsyon-technologies.com" >> /etc/hosts

cd $(dirname $(readlink -f $0))

www="www.web-site.com"

[ -e /tmp/$www ] && rm -rf /tmp/$www
[ -e /etc/apache2/site-available/$www ] && rm -rf /etc/apache2/site-available/$www
[ -n "$(echo "\l" | psql | grep $www)" ] && dropdb $www

cp -r $www /tmp/

sed -i "s/\/data\/www/\/tmp/" /tmp/$www/vhost-$www

# The first grant is here to enable the drop user even if the user did not exist.
echo "drop database if exists www_web_site_com;
grant usage on *.* to www_web;
drop user www_alsyon;
create user www_web identified by 'pwd';
create database www_web_site_com character set UTF8;
grant all on www_web_site_com.* to www_web;" | mysql -u root -p
cat /tmp/$www/dump-www_web_site.sql | mysql -u root -p

sed -i "s/define('DB_PASSWORD', 'W3nxU2VQb9zjiLA');/define('DB_PASSWORD', 'pwd');/" /tmp/$www/wp-config.php

sudo ln -sf /tmp/$www/vhost-$www /etc/apache2/sites-available/$www
sudo a2ensite $www
sudo /etc/init.d/apache2 restart

sudo tail -F /var/log/apache2/www.web_site.com-access.log /var/log/apache2/www.web_site.com-error.log

