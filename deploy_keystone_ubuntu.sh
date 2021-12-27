#!/bin/bash
#
# Openstack controller installation
# You need 2 network adapters in 2 differents VLAN
# 192.168.0.0/24
# 10.0.0.0/24
#
# This OpenStack Hosts will use 10.0.0.0/24 network
# You need to setup manually ip address to 10.0.0.11
#
#
# 10.0.0.11 opnstack-controller-01.rootly.local opnstack-controller-01
# 10.0.0.31 opnstack-compute-01.rootly.local opnstack-compute-01
# 10.0.0.41 opnstack-block-01.rootly.local opnstack-block-01
# 10.0.0.51 opnstack-object01.rootly.local opnstack-object01
# 10.0.0.52 opnstack-object02.rootly.local opnstack-object02

OP_CONTROLLER_IP=10.0.0.11
PASS_LEN=25
### PRE-TESTING

if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
  echo "Internet connection OK"
else
  echo "Internet connection NOK"
  echo "We must exit this script, sorry"
  exit 1
fi

### Upgrade system

apt update
apt upgrade -y

### Install and configure NTP server

apt install chrony -y
echo 'allow 10.0.0.0/24' | tee -a /etc/chrony/chrony.conf
systemctl restart chrony.service
systemctl enable chrony.service

### Enable Openstack Package

apt update
apt install python3-openstackclient -y

### Install and configure MariaDB
apt install mariadb-server python3-pymysql -y

cat << EOF > /etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = ${OP_CONTROLLER_IP}

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

systemctl restart mariadb.service
systemctl enable mariadb.service

DB_ROOT_PASS=$(openssl rand -hex $PASS_LEN)
echo $DB_ROOT_PASS | tee -a /root/database_root_pass.txt

mysql <<_EOF_
  UPDATE mysql.user SET Password=PASSWORD('${DB_ROOT_PASS}') WHERE User='root';
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
  FLUSH PRIVILEGES;
_EOF_

### Install and configure rabbitmq-server

apt install rabbitmq-server -y

RABBIT_PASS=$(openssl rand -hex $PASS_LEN)
echo $RABBIT_PASS | tee -a /root/rabbit_pass.txt
rabbitmqctl add_user openstack $RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

### Install memcache

apt install memcached python3-memcache -y
sed -i 's/-l 127.0.0.1/-l ${OP_CONTROLLER_IP}/g' /etc/memcached.conf
systemctl restart memcached
systemctl enable memcached

### install etcd

apt install etcd -y

cat << EOF >> /etc/default/etcd

ETCD_NAME="$HOSTNAME"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER="$HOSTNAME=http://${OP_CONTROLLER_IP}:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${OP_CONTROLLER_IP}:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://${OP_CONTROLLER_IP}:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://${OP_CONTROLLER_IP}:2379"
EOF

systemctl restart etcd
systemctl enable etcd

### configure and install keystone

KEYSTONE_DBPASS=$(openssl rand -hex $PASS_LEN)
echo $KEYSTONE_DBPASS | tee -a /root/keystone_db_pass.txt

mysql <<_EOF_
  CREATE DATABASE keystone;
  GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}';
  GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}';
_EOF_

apt install keystone -y

echo "@@-> Edit the /etc/keystone/keystone.conf -> https://docs.openstack.org/keystone/wallaby/install/keystone-install-ubuntu.html"

echo connection = mysql+pymysql://keystone:$KEYSTONE_DBPASS@$HOSTNAME/keystone

su -s /bin/sh -c "keystone-manage db_sync" keystone

keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

ADMIN_PASS=$(openssl rand -hex $PASS_LEN)
echo $ADMIN_PASS | tee -a /root/admin_pass.txt

keystone-manage bootstrap --bootstrap-password $ADMIN_PASS --bootstrap-admin-url http://$HOSTNAME:5000/v3/ --bootstrap-internal-url http://$HOSTNAME:5000/v3/ --bootstrap-public-url http://$HOSTNAME:5000/v3/ --bootstrap-region-id RegionOne

echo "@@-> Edit the /etc/apache2/apache2.conf -> https://docs.openstack.org/keystone/wallaby/install/keystone-install-ubuntu.html"

systemctl restart apache2.service
systemctl enable apache2.service


echo "###"
echo "As normal user, execute the following to test installation"
echo ""
echo export OS_USERNAME=admin
echo export OS_PASSWORD=$ADMIN_PASS
echo export OS_PROJECT_NAME=admin
echo export OS_USER_DOMAIN_NAME=Default
echo export OS_PROJECT_DOMAIN_NAME=Default
echo export OS_AUTH_URL=http://$HOSTNAME:5000/v3
echo export OS_IDENTITY_API_VERSION=3
echo ""

##### AS USER #####
echo ""
echo 'openstack domain create --description "An Example Domain" example'
echo 'openstack project create --domain default --description "Service Project" service'
echo ""
echo 'openstack project create --domain default --description "Demo Project" myproject'
echo 'openstack user create --domain default --password-prompt myuser'
echo ""
echo 'openstack role create myrole'
echo 'openstack role add --project myproject --user myuser myrole'
echo ""
echo ""
#### TESTING

echo unset OS_AUTH_URL OS_PASSWORD
echo openstack --os-auth-url http://$HOSTNAME:5000/v3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name admin --os-username admin token issue
echo openstack --os-auth-url http://$HOSTNAME:5000/v3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name myproject --os-username myuser token issue
