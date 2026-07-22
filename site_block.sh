#!/bin/bash

set -eu

ufw --force reset

ufw default deny incoming
ufw default deny outgoing

ufw allow in on lo
ufw allow out on lo

# Allow SSH (incoming and outgoing responses)
ufw allow in proto tcp to any port 22
ufw allow out proto tcp from any port 22

# Allow DNS outgoing
ufw allow out proto udp to any port 53

# Allow HTTP/HTTPS outgoing to specific IP
ufw allow out to 95.163.252.67 proto tcp port 80
ufw allow out to 95.163.252.67 proto tcp port 443

# Allow HTTP/HTTPS incoming
ufw allow in proto tcp from any to any port 80
ufw allow in proto tcp from any to any port 443

ufw --force enable

echo "DONE"