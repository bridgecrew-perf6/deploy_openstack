clear

PASS_LEN=25
. admin-openrc
LOGFILE=deploy_nova_controller.log
touch $LOGFILE

NOVA_DBPASS=$(openssl rand -hex $PASS_LEN) &> $LOGFILE

mysql <<_EOF_
  CREATE DATABASE nova_api;
  CREATE DATABASE nova;
  CREATE DATABASE nova_cell0;
_EOF_

mysql <<_EOF_
  GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}';
  GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';
  GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}';
  GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';
  GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}';
  GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';
_EOF_

NOVA_ADMINPASS=$(openssl rand -hex $PASS_LEN) &> $LOGFILE

openstack user create --domain default --password ${NOVA_ADMINPASS} nova
openstack role add --project service --user nova admin

openstack service create --name nova --description "OpenStack Compute" compute

openstack endpoint create --region RegionOne compute public http://${HOSTNAME}:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://${HOSTNAME}:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://${HOSTNAME}:8774/v2.1

apt install -y nova-api nova-conductor nova-novncproxy nova-scheduler

NOVA_API_CON="mysql+pymysql://nova:${NOVA_DBPASS}@${HOSTNAME}/nova_api"
NOVA_CON="mysql+pymysql://nova:${NOVA_DBPASS}@${HOSTNAME}/nova"

crudini --set /etc/nova/nova.conf api_database connection $NOVA_API_CONN
crudini --set /etc/nova/nova.conf database connection $NOVA_CON
crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@${HOSTNAME}:5672/
crudini --set /etc/nova/nova.conf api auth_strategy keystone

crudini --set /etc/nova/nova.conf keystone_authtoken www_authenticate_uri 
crudini --set /etc/nova/nova.conf keystone_authtoken auth_url 
crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers 
crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name Default
crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name Default
crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
crudini --set /etc/nova/nova.conf keystone_authtoken username nova
crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_ADMINPASS

crudini --set /etc/nova/nova.conf DEFAULT my_ip $OP_CONTROLLER_IP
crudini --set /etc/nova/nova.conf vnc enabled true
crudini --set /etc/nova/nova.conf vnc server_listen $my_ip
crudini --set /etc/nova/nova.conf vnc server_proxyclient_address $my_ip

crudini --set /etc/nova/nova.conf glance api_servers http://${HOSTNAME}:9292
crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp

crudini --set /etc/nova/nova.conf placement region_name RegionOne
crudini --set /etc/nova/nova.conf placement project_domain_name Default
crudini --set /etc/nova/nova.conf placement project_name service
crudini --set /etc/nova/nova.conf placement auth_type password
crudini --set /etc/nova/nova.conf placement user_domain_name Default
crudini --set /etc/nova/nova.conf placement auth_url http://${HOSTNAME}:5000/v3
crudini --set /etc/nova/nova.conf placement username placement
crudini --set /etc/nova/nova.conf placement password $PLACEMENT_ADMINPASS

crudini --set /etc/nova/nova.conf scheduler discover_hosts_in_cells_interval 300

su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova

echo export NOVA_DBPASS=$NOVA_DBPASS >> admin-openrc
echo export NOVA_ADMINPASS=$NOVA_ADMINPASS >> admin-openrc

service nova-api restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart
