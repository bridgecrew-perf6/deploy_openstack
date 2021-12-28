clear

PASS_LEN=25
source admin-openrc
LOGFILE=deploy_placement.log
touch $LOGFILE

PLACEMENT_DBPASS=$(openssl rand -hex $PASS_LEN) &> $LOGFILE


mysql <<_EOF_
  CREATE DATABASE placement;
  GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '${PLACEMENT_DBPASS}';
  GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '${PLACEMENT_DBPASS}';
_EOF_

PLACEMENT_ADMINPASS=$(openssl rand -hex $PASS_LEN) &> $LOGFILE


openstack user create --domain default --password ${PLACEMENT_ADMINPASS} placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement

openstack endpoint create --region RegionOne placement public http://${HOSTNAME}:8778
openstack endpoint create --region RegionOne placement internal http://${HOSTNAME}:8778
openstack endpoint create --region RegionOne placement admin http://${HOSTNAME}:8778

apt install -y placement-api

PLACEMENT_CON="mysql+pymysql://placement:${PLACEMENT_DBPASS}@${HOSTNAME}/placement"

crudini --set /etc/placement/placement.conf placement_database connection $PLACEMENT_CON
crudini --set /etc/placement/placement.conf api auth_strategy keystone
crudini --set /etc/placement/placement.conf keystone_authtoken auth_url http://${HOSTNAME}:5000/v3
crudini --set /etc/placement/placement.conf keystone_authtoken memcached_servers = ${HOSTNAME}:11211
crudini --set /etc/placement/placement.conf keystone_authtoken auth_type = password
crudini --set /etc/placement/placement.conf keystone_authtoken project_domain_name = Default
crudini --set /etc/placement/placement.conf keystone_authtoken user_domain_name = Default
crudini --set /etc/placement/placement.conf keystone_authtoken project_name = service
crudini --set /etc/placement/placement.conf keystone_authtoken username = placement
crudini --set /etc/placement/placement.conf keystone_authtoken password = $PLACEMENT_ADMINPASS

su -s /bin/sh -c "placement-manage db sync" placement

service apache2 restart

echo export PLACEMENT_DBPASS=$PLACEMENT_DBPASS >> admin-openrc
echo export PLACEMENT_ADMINPASS=$PLACEMENT_ADMINPASS >> admin-openrc
