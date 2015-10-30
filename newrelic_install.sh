#!/bin/sh
INSTANCE_ID=`/usr/bin/curl -s http://169.254.169.254/latest/meta-data/instance-id`
NR_INSTALL_KEY="${LICENSE_KEY}"
NR_INSTALL_SILENT="silent"
if [ "${NR_INSTALL_KEY}" = "" ]; then
  echo "Please set environment variable 'LICENSE_KEY'."
  exit 1
fi

export NR_INSTALL_KEY
export NR_INSTALL_SILENT

# install newrelic sysmond
rpm -Uvh https://yum.newrelic.com/pub/newrelic/el5/x86_64/newrelic-repo-5-3.noarch.rpm
yum -y install newrelic-sysmond
nrsysmond-config --set license_key=${NR_INSTALL_KEY}
service newrelic-sysmond start
chkconfig newrelic-sysmond on

# install newrelic php
yum -y install newrelic-php5
newrelic-install install
cp -p /etc/newrelic/newrelic.cfg.template /etc/newrelic/newrelic.cfg
sed -i -e "s/newrelic.appname = \"PHP Application\"/newrelic.appname = \"${INSTANCE_ID} PHP Application\"/g" /etc/php.d/newrelic.ini
chkconfig newrelic-daemon on
service php-fpm restart
service newrelic-daemon restart

# install mysql plugin
if [ "${NR_MYSQL_PLUGIN_INSTALL}" = "install" ]; then
  PREFIX="${HOME}/newrelic-npi"
  mysql -u root -e \
  "CREATE USER newrelic@localhost IDENTIFIED BY '${INSTANCE_ID}'; GRANT PROCESS,REPLICATION CLIENT ON *.* TO newrelic@localhost;"
  yes | LICENSE_KEY="${NR_INSTALL_KEY}" bash -c "$(curl -sSL https://download.newrelic.com/npi/release/install-npi-linux-redhat-x64.sh)"
  cd ${PREFIX}
  ./npi config set license_key ${NR_INSTALL_KEY}
  ./npi install nrmysql -y -q -n
  PLUGIN_JSON=${PREFIX}/plugins/com.newrelic.plugins.mysql.instance/newrelic_mysql_plugin-2.0.0/config/plugin.json
  sed -i -e "s/Localhost/${INSTANCE_ID} MySQL/g" ${PLUGIN_JSON}
  sed -i -e "s/USER_NAME_HERE/newrelic/g" ${PLUGIN_JSON}
  sed -i -e "s/USER_PASSWD_HERE/${INSTANCE_ID}/g" ${PLUGIN_JSON}
  chkconfig newrelic_plugin_com.newrelic.plugins.mysql.instance on
  service newrelic_plugin_com.newrelic.plugins.mysql.instance restart
fi

# monit setting
echo 'check process newrelic-sysmond
  with pidfile /var/run/newrelic/nrsysmond.pid
  start program = "/sbin/service newrelic-sysmond start"
  stop program = "/sbin/service newrelic-sysmond stop"

check process newrelic-daemon
  with pidfile /var/run/newrelic-daemon.pid
  start program = "/sbin/service newrelic-daemon start"
  stop program = "/sbin/service newrelic-daemon stop"
' > /etc/monit.d/newrelic

if [ "${NR_MYSQL_PLUGIN_INSTALL}" = "install" ]; then
  echo '
check process newrelic_plugin_com.newrelic.plugins.mysql.instance
  with pidfile /var/run/newrelic_plugin_com.newrelic.plugins.mysql.instance.pid
  start program = "/sbin/service newrelic_plugin_com.newrelic.plugins.mysql.instance start"
  stop program = "/sbin/service newrelic_plugin_com.newrelic.plugins.mysql.instance stop"' >> /etc/monit.d/newrelic
fi
service monit restart
