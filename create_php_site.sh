#!/bin/bash


# Modify the following to match your system
NGINX_CONFIG='/etc/nginx/sites-available'
NGINX_SITES_ENABLED='/etc/nginx/conf.d/'
PHP_INI_DIR='/etc/php/7.0/fpm/pool.d'
WEB_SERVER_GROUP='nginx'
NGINX_INIT='/etc/init.d/nginx'
PHP_FPM_INIT='/etc/init.d/php7.0-fpm'
# --------------END
SED=`which sed`
CURRENT_DIR=`dirname $0`

if [ -z $1 ]; then
	echo "No domain name given"
	exit 1
fi
DOMAIN=$1

# check the domain is valid!
PATTERN="^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$";
if [[ "$DOMAIN" =~ $PATTERN ]]; then
	DOMAIN=`echo $DOMAIN | tr '[A-Z]' '[a-z]'`
	echo "Creating hosting for:" $DOMAIN
else
	echo "invalid domain name"
	exit 1
fi

# Create a new user!
echo "Please specify the username for this site?"
read USERNAME
HOME_DIR=$USERNAME
adduser $USERNAME

echo "Would you like to change to web root directory (y/n)?"
read CHANGEROOT
if [ $CHANGEROOT == "y" ]; then
	echo "Enter the new web root dir (after the public_html/)"
	read DIR
	PUBLIC_HTML_DIR='/public_html/'$DIR
else
	PUBLIC_HTML_DIR='/public_html'
fi

# Now we need to copy the virtual host template
CONFIG=$NGINX_CONFIG/$DOMAIN.conf
cp $CURRENT_DIR/nginx.vhost.conf.template $CONFIG
$SED -i "s/@@HOSTNAME@@/$DOMAIN/g" $CONFIG
$SED -i "s#@@PATH@@#\/home\/main\/"$USERNAME$PUBLIC_HTML_DIR"#g" $CONFIG
$SED -i "s/@@LOG_PATH@@/\/home\/main\/$USERNAME\/_logs/g" $CONFIG
$SED -i "s#@@SOCKET@@#/var/run/"$USERNAME"_fpm.sock#g" $CONFIG

echo "How many FPM servers would you like by default:"
read FPM_SERVERS
echo "Min number of FPM servers would you like:"
read MIN_SERVERS
echo "Max number of FPM servers would you like:"
read MAX_SERVERS
# Now we need to create a new php fpm pool config
FPMCONF="$PHP_INI_DIR/$DOMAIN.pool.conf"

cp $CURRENT_DIR/pool.conf.template $FPMCONF

$SED -i "s/@@USER@@/$USERNAME/g" $FPMCONF
$SED -i "s/@@HOME_DIR@@/\/home\/main\/$USERNAME/g" $FPMCONF
$SED -i "s/@@START_SERVERS@@/$FPM_SERVERS/g" $FPMCONF
$SED -i "s/@@MIN_SERVERS@@/$MIN_SERVERS/g" $FPMCONF
$SED -i "s/@@MAX_SERVERS@@/$MAX_SERVERS/g" $FPMCONF
MAX_CHILDS=$((MAX_SERVERS+START_SERVERS))
$SED -i "s/@@MAX_CHILDS@@/$MAX_CHILDS/g" $FPMCONF

usermod -aG $USERNAME $WEB_SERVER_GROUP
chmod g+rx /home/main/$HOME_DIR
chmod 600 $CONFIG

ln -s $CONFIG $NGINX_SITES_ENABLED/$DOMAIN.conf

# set file perms and create required dirs!
mkdir -p /home/main/$HOME_DIR$PUBLIC_HTML_DIR
mkdir /home/main/$HOME_DIR/_logs
mkdir /home/main/$HOME_DIR/_sessions
chmod 750 /home/main/$HOME_DIR -R
chmod 700 /home/main/$HOME_DIR/_sessions
chmod 770 /home/main/$HOME_DIR/_logs
chmod 750 /home/main/$HOME_DIR$PUBLIC_HTML_DIR

# Install latest version Wordpress
cd /home/main/$HOME_DIR$PUBLIC_HTML_DIR
wget "https://wordpress.org/latest.zip";
unzip latest.zip
mv -a /home/main/$HOME_DIR$PUBLIC_HTML_DIR/wordpress/* /home/main/$HOME_DIR$PUBLIC_HTML_DIR/

chown $USERNAME:$USERNAME /home/main/$HOME_DIR/ -R

# Install certbot
sudo certbot --authenticator standalone --installer nginx -d $DOMAIN --pre-hook "/etc/init.d/nginx stop" --post-hook "/etc/init.d/nginx start"

# Creat DB user and password

mysql -u root -p

CREATE USER '$USERNAME'@'localhost' IDENTIFIED BY 'password';

CREATE DATABASE DB_$USERNAME;

GRANT ALL PRIVILEGES ON DB_$USERNAME. * TO '$USERNAME'@'localhost' IDENTIFIED BY 'password';

FLUSH PRIVILEGES;
exit

# Crontab Certbot renew
sudo crontab -e
00 2 1 * * /usr/bin/certbot renew -q
00 2 15 * * /usr/bin/certbot renew -q


$NGINX_INIT reload
$PHP_FPM_INIT restart

echo -e "\nSite Created for $DOMAIN with PHP support"
