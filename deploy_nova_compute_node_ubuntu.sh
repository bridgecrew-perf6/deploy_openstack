clear

PASS_LEN=25
. admin-openrc
LOGFILE=deploy_nova_compute_node.log
touch $LOGFILE

apt install -y crudini nova-compute

crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:$RABBIT_PASS@${OS_CONTROLLER}

crudini --set /etc/nova/nova.conf api auth_strategy keystone

crudini --set /etc/nova/nova.conf keystone_authtoken www_authenticate_uri http://${OS_CONTROLLER}:5000/
crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://${OS_CONTROLLER}:5000/
crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers ${OS_CONTROLLER}:11211
crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name Default
crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name Default
crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
crudini --set /etc/nova/nova.conf keystone_authtoken username nova
crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_ADMINPASS

crudini --set /etc/nova/nova.conf DEFAULT my_ip MANAGEMENT_INTERFACE_IP_ADDRESS *********************************************
crudini --set /etc/nova/nova.conf vnc enabled true
crudini --set /etc/nova/nova.conf vnc server_listen 0.0.0.0
crudini --set /etc/nova/nova.conf vnc server_proxyclient_address '$my_ip'
crudini --set /etc/nova/nova.conf vnc novncproxy_base_url http://${OS_CONTROLLER}:6080/vnc_auto.html

crudini --set /etc/nova/nova.conf glance api_servers http://${OS_CONTROLLER}:9292
crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp

crudini --set /etc/nova/nova.conf placement region_name RegionOne
crudini --set /etc/nova/nova.conf placement project_domain_name Default
crudini --set /etc/nova/nova.conf placement project_name service
crudini --set /etc/nova/nova.conf placement auth_type password
crudini --set /etc/nova/nova.conf placement user_domain_name Default
crudini --set /etc/nova/nova.conf placement auth_url http://${OS_CONTROLLER}:5000/v3
crudini --set /etc/nova/nova.conf placement username placement
crudini --set /etc/nova/nova.conf placement password ${PLACEMENT_ADMINPASS}

crudini --set /etc/nova/nova-compute.conf libvirt virt_type qemu

service nova-compute restart
