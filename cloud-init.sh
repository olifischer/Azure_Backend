#! /bin/bash

sudo echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sudo echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sudo sysctl -p /etc/sysctl.conf