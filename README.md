# deploy_openstack
cd ~

wget https://github.com/rootly-be/deploy_openstack/raw/main/deploy_keystone_ubuntu.sh

chmod +x deploy_keystone_ubuntu.sh

./deploy_keystone_ubuntu.sh

wget https://github.com/rootly-be/deploy_openstack/raw/main/deploy_glance_ubuntu.sh

chmod +x deploy_glance_ubuntu.sh

./deploy_glance_ubuntu.sh

wget https://github.com/rootly-be/deploy_openstack/raw/main/deploy_placement_ubuntu.sh

chmod +x deploy_placement_ubuntu.sh

./deploy_placement_ubuntu.sh
