clear

PASS_LEN=25
source admin-openrc
LOGFILE=deploy_glance.log
touch $LOGFILE

GLANCE_DBPASS=$(openssl rand -hex $PASS_LEN) &> $LOGFILE
echo $GLANCE_DBPASS > /root/glance_db_pass.txt

mysql <<_EOF_
  CREATE DATABASE glance;
  GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '${GLANCE_DBPASS}';
  GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '${GLANCE_DBPASS}';
_EOF_

GLANCE_ADMINPASS=$(openssl rand -hex $PASS_LEN) &> $LOGFILE
echo $GLANCE_ADMINPASS > /root/glance_admin_pass.txt

openstack user create --domain default --password ${GLANCE_ADMINPASS} glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://${HOSTNAME}:9292
openstack endpoint create --region RegionOne image internal http://${HOSTNAME}:9292
openstack endpoint create --region RegionOne image admin http://${HOSTNAME}:9292

apt install -y glance

GLANCE_CON="mysql+pymysql://glance:${GLANCE_DBPASS}@${HOSTNAME}/glance"

crudini --set /etc/glance/glance-api.conf database connection $GLANCE_CON

crudini --set /etc/glance/glance-api.conf keystone_authtoken www_authenticate_uri http://${HOSTNAME}:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://${HOSTNAME}:5000
crudini --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers ${HOSTNAME}:11211
crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name Default
crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name Default
crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
crudini --set /etc/glance/glance-api.conf keystone_authtoken username glance
crudini --set /etc/glance/glance-api.conf keystone_authtoken password $GLANCE_ADMINPASS

crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone

crudini --set /etc/glance/glance-api.conf glance_store stores file,http
crudini --set /etc/glance/glance-api.conf glance_store default_store file
crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/

su -s /bin/sh -c "glance-manage db_sync" glance

systemctl restart glance-api

wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
glance image-create --name "cirros" --file cirros-0.4.0-x86_64-disk.img --disk-format qcow2 --container-format bare --visibility=public
