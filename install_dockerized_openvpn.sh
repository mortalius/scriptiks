#!/bin/bash
# https://github.com/kylemanna/docker-openvpn
# for Ubuntu 16
set -x

OVPN_DATA="ovpn-castle"
SERVER_NAME="vpn.arrm.ru"
CLIENT_NAME="mort"

# Install docker
apt update
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
apt-add-repository 'deb https://apt.dockerproject.org/repo ubuntu-xenial main'
apt update
apt install -y docker-engine

# Initialize the $OVPN_DATA container that will hold the configuration files and certificates.
docker volume create --name $OVPN_DATA
docker run -v $OVPN_DATA:/etc/openvpn --rm kylemanna/openvpn ovpn_genconfig -u udp://$SERVER_NAME
docker run -v $OVPN_DATA:/etc/openvpn --rm -it kylemanna/openvpn ovpn_initpki

# ! Start OpenVPN server process !
docker run -v $OVPN_DATA:/etc/openvpn -d -p 1194:1194/udp --cap-add=NET_ADMIN kylemanna/openvpn

#Generate a client certificate without a passphrase
docker run -v $OVPN_DATA:/etc/openvpn --rm -it kylemanna/openvpn easyrsa build-client-full $CLIENT_NAME nopass

#Retrieve the client configuration with embedded certificates
docker run -v $OVPN_DATA:/etc/openvpn --rm kylemanna/openvpn ovpn_getclient $CLIENT_NAME > $CLIENT_NAME.ovpn


# Debug or run
# docker run -v $OVPN_DATA:/etc/openvpn -p 1194:1194/udp --privileged -e DEBUG=1 kylemanna/openvpn
# docker run -v $OVPN_DATA:/etc/openvpn -p 1194:1194/udp --privileged kylemanna/openvpn
