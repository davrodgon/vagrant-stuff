export DEBIAN_FRONTEND="noninteractive"

LORISADMIN_UID=1002
LORISADMIN_GID=1002

sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password '$MYSQL_ROOT_PASSWORD
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password '$MYSQL_ROOT_PASSWORD

sudo add-apt-repository ppa:ondrej/php5-5.6

sudo apt-get update

sudo apt-get install -y expect apache2 libapache2-mod-php5 libmysqlclient15-dev mysql-client-5.5 mysql-server-5.5 php5 php5-mysql php5-gd php5-sqlite php-pear php5-json smarty3

SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"$MYSQL_ROOT_PASSWORD\r\"
expect \"Change the root password?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")

echo "$SECURE_MYSQL"

echo "Install Composer"
curl -sS https://getcomposer.org/installer | php;
sudo mv composer.phar /usr/local/bin/composer

echo "Create lorisadmin user and group"
sudo groupadd --gid 1002 lorisadmin
sudo useradd --uid 1002 --gid 1002 -m -G sudo -s /bin/bash lorisadmin
echo "Adding users to groups"
sudo usermod -a -G www-data lorisadmin
sudo usermod -a -G www-data vagrant
sudo usermod -a -G vagrant apache

CHANGE_PASSWORD=$(expect -c "
set timeout 10
spawn sudo passwd lorisadmin
expect \"Enter new UNIX password:\"
send \"$LORISADMIN_PASSWORD\r\"
expect \"Retype new UNIX password:\"
send \"$LORISADMIN_PASSWORD\r\"
expect eof
")

echo "$CHANGE_PASSWORD"

echo "Download Loris" 
echo "Clone to /var/www/loris"
sudo apt-get install -y git
sudo git clone -b $LORIS_VERSION https://github.com/aces/Loris.git /var/www/loris

echo "Change permissions"
sudo chown 775 /var/www/loris
sudo chown -R lorisadmin:lorisadmin /var/www/loris

echo "Execute install script"
cd /var/www/loris/tools

INSTALL_LORIS=$(expect -c "
set timeout 10
spawn ./install.sh
expect \"Ready to continue? \[yn\]\"
send \"y\r\"
expect \"Enter project name:\"
send \"loris\r\"
expect \"What is the database name?\"
send \"loris\r\"
expect \"Database host?\"
send \"localhost\r\"
expect \"What MySQL user will LORIS connect as? (Recommended: lorisuser)\"
send \"lorisuser\r\"
expect \"What is the host from which MySQL user 'lorisuser' will connect? (Where Loris' Apache is hosted)\"
send \"localhost\r\"
expect \"Choose a password for MySQL user 'lorisuser'?\"
send \"$MYSQL_LORISUSER_PASSWORD\r\"
expect \"Re-enter the password to check for accuracy:\"
send \"$MYSQL_LORISUSER_PASSWORD\r\"
expect \"Choose a different password for the front-end LORIS 'admin' user account:\"
send \"$WEB_ADMIN_PASSWORD\r\"
expect \"Re-enter the password to check for accuracy:\"
send \"$WEB_ADMIN_PASSWORD\r\"
expect \"Existing root or admin-level MySQL username:\"
send \"root\r\"
expect \"MySQL password for user 'root':\"
send \"$MYSQL_ROOT_PASSWORD\r\"
expect \"Re-enter the password to check for accuracy:\"
send \"$MYSQL_ROOT_PASSWORD\r\"
expect \"Would you like to automatically create the MySQL database for LORIS? \[yn\]\"
send \"y\r\"
expect \"Would you like to automatically create and grant privileges to MySQL user 'lorisuser'@'localhost'? \[yn\]\"
send \"y\r\"
expect \"Would you like to automatically create/populate database tables from schema? \[yn\]\"
send \"y\r\"
expect \"Would you like to automatically populate database config? \[yn\]\"
send \"y\r\"
expect \"Would you like to automatically create/install apache config files? (Works for Ubuntu 14.04 default Apache installations) \[yn\]\"
send \"y\r\"
expect eof
")

sudo -u lorisadmin echo "$INSTALL_LORIS"

sudo chown -R lorisadmin:lorisadmin /var/www/loris

sudo a2enmod rewrite
sudo service apache2 reload

# Changes to Loris Config in database 
echo "update Config set Value='${LORIS_URL}' where ConfigID=(select ID from ConfigSettings where Name='url');" | mysql -u lorisuser --password="$MYSQL_LORISUSER_PASSWORD" loris

echo "Restart Apache"
sudo service apache2 restart

echo "Install Images Pipeline"
echo "Installing dependencies first"
sudo apt-get install -y libc6 libstdc++6 imagemagick perl
cd /home/vagrant
wget -o wget-minc-toolkit.weblog http://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/minc-toolkit-1.0.08-20160205-Ubuntu_14.04-x86_64.deb
wget -o wget-minc-testsuite.weblog http://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/minc-toolkit-testsuite-0.1.3-20131212.deb
wget -o wget-beast.weblog http://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/beast-library-1.1.0-20121212.deb
wget -o wget-models.weblog http://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/bic-mni-models-0.1.1-20120421.deb

sudo dpkg -i minc-toolkit-1.0.08-20160205-Ubuntu_14.04-x86_64.deb minc-toolkit-testsuite-0.1.3-20131212.deb bic-mni-models-0.1.1-20120421.deb beast-library-1.1.0-20121212.deb

sudo apt-get install -f
echo "Cleanup"
rm *.deb *.weblog

echo "Config MINC toolkit"
source /opt/minc/minc-toolkit-config.sh
 
sudo apt-get install -y libgl1-mesa-glx libglu1-mesa

echo "Install pipeline from Git"
sudo apt-get install -y git
sudo mkdir -p /data/loris/bin/mri
sudo chown -R lorisadmin:lorisadmin /data
cd /data/loris/bin
git clone https://github.com/aces/Loris-MRI.git mri
cd /data/loris/bin/mri
git submodule init
git submodule sync
git submodule update

echo "Execute imaging_install script"

INSTALL_IMAGING=$(expect -c "
set timeout 10
spawn ./imaging_install.sh
expect \"What is the database name?\"
send \"loris\r\"
expect \"What is the database host?\"
send \"localhost\r\"
expect \"What is the MySQL user?\"
send \"lorisuser\r\"
expect \"What is the MySQL password?\"
send \"$MYSQL_LORISUSER_PASSWORD\r\"
expect \"What is the Linux user which the installation will be based on?\"
send \"lorisadmin\r\"
expect \"What is the project name?\"
send \"loris\r\"
expect \"What is your email address?\"
send \"david.rodriguez@ed.ac.uk\r\"
expect \"What prod file name would you like to use? default: prod\"
send \"\r\"
expect \"Enter the list of Site names (space separated)\"
send \"BRIC\r\"
expect \"Do you want to continue? \[Y/n\]\"
send \"Y\r\"
expect \"Would you like to configure as much as possible automatically? \[yes\]\"
send \"\r\"
expect \"Would you like me to automatically choose some CPAN mirror sites for you? (This means connecting to the Internet) \[yes\]\"
send \"\r\"

expect eof
")

echo "$INSTALL_IMAGING"

echo "Source environment in bashrc"
sudo -u lorisadmin sh -c 'echo "source /data/loris/bin/mri/environment" >> /home/lorisadmin/.bashrc'

echo "Setup daily backups to /data/backup"
mkdir /home/vagrant/scripts
echo 'mysqldump -u root -p$1 loris | gzip > /data/backup/loris-`date +\%Y\%m\%d`.sql.gz' > /home/vagrant/scripts/backup-loris.sh 
chmod a+x /home/vagrant/scripts/backup-loris.sh
mkdir -p /data/backup
echo "05 01 * * *  /home/vagrant/scripts/backup-loris.sh $MYSQL_ROOT_PASSWORD" | crontab

