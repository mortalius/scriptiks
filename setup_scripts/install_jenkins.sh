#!/usr/bin/env bash

yum -y update
yum install -y git  java-1.8.0-openjdk-devel aws-cli nginx
alternatives --config java

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key

yum install -y jenkins

# Move home to /local
mkdir -p /local/jenkins
sed -i -r -e 's/(JENKINS_HOME)="(.+)"/\1="\/local\/jenkins"/' /etc/sysconfig/jenkins

service jenkins start
chkconfig jenkins on

truncate -s 0 /etc/nginx/nginx.conf
echo "
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;
    server {
        listen 80;
        server_name _;
        location / {
            proxy_pass http://127.0.0.1:8080;
        }
    }
}
" >> /etc/nginx/nginx.conf

service nginx start
chkconfig nginx on

# alternative to nginx
# iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
# service iptables save

PSWD=`cat /var/lib/jenkins/secrets/initialAdminPassword`
echo "Login - admin"
echo "Password is $PSWD"
