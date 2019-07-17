#!/bin/bash
set -e

ZABBIX_SERVER=195.201.4.82
ZABBIX_ACTIVE=195.201.4.82
DOMAIN=miditex.ru

RELEASE_CODENAME=$(lsb_release --short --codename)

if [[ ! $RELEASE_CODENAME =~ xenial|trusty ]]; then
    echo "We support only xenial or trusty Ubuntus"
    exit 1
fi

wget http://repo.zabbix.com/zabbix/3.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_3.4-1+${RELEASE_CODENAME}_all.deb
dpkg -i zabbix-release_3.4-1+${RELEASE_CODENAME}_all.deb 

apt-get -y update
apt-get -y install zabbix-agent

# Указываем сервак и ServerActive для получения Active метрик
sed -r -i -e "s/^Server=.*/Server=$ZABBIX_SERVER/" /etc/zabbix/zabbix_agentd.conf
sed -r -i -e "s/^ServerActive=.*/ServerActive=$ZABBIX_ACTIVE/" /etc/zabbix/zabbix_agentd.conf 

# Насильно указываем домен для машин где его нет, чтобы в заббиксе отличать с какого Края пришла машина
SHORT_HOSTNAME=$(hostname -s)
sed -r -i -e "s/^Hostname=.*/Hostname=$SHORT_HOSTNAME\.$DOMAIN/" /etc/zabbix/zabbix_agentd.conf 

egrep "^Hostname|^Server" /etc/zabbix/zabbix_agentd.conf

if [[ $RELEASE_CODENAME == "xenial" ]]; then
    systemctl enable zabbix-agent.service
    systemctl start zabbix-agent.service 
elif [[ $RELEASE_CODENAME == "trusty" ]]; then
    update-rc.d zabbix-agent enable
    service zabbix-agent restart
fi

exit 0


#### RHEL/CENTOS

wget http://repo.zabbix.com/zabbix/3.4/rhel/6/x86_64/zabbix-release-3.4-1.el6.noarch.rpm
wget http://repo.zabbix.com/zabbix/3.4/rhel/7/x86_64/zabbix-release-3.4-1.el7.centos.noarch.rpm
rpm -i zabbix-release-3.4-1.el7.centos.noarch.rpm
yum install -y zabbix-agent

ZABBIX_SERVER=195.201.4.82
ZABBIX_ACTIVE=195.201.4.82
DOMAIN=soho.co
sed -r -i -e "s/^Server=.*/Server=$ZABBIX_SERVER/" /etc/zabbix/zabbix_agentd.conf
sed -r -i -e "s/^ServerActive=.*/ServerActive=$ZABBIX_ACTIVE/" /etc/zabbix/zabbix_agentd.conf 
SHORT_HOSTNAME=$(hostname -s)
sed -r -i -e "s/^Hostname=.*/Hostname=$SHORT_HOSTNAME\.$DOMAIN/" /etc/zabbix/zabbix_agentd.conf 
egrep "^Hostname|^Server" /etc/zabbix/zabbix_agentd.conf

chkconfig zabbix-agent on



VALUE="$(date --rfc-3339=ns)"; zabbix_sender \
    --zabbix-server=127.0.0.1 \
    --host="Zabbix server" \
    --key="test.timestamp" \
    --value="${VALUE}"

zabbix_sender \
    --zabbix-server=127.0.0.1 \
    --host="Zabbix server" \
    --key="test.timestamp" \
    --value="${VALUE}"