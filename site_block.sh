#!/bin/bash

set -eu

echo "y" | ufw reset

ufw default deny incoming
ufw default deny outgoing

ufw allow in on lo
ufw allow out on lo

ufw allow in proto tcp to any port 22

ufw allow out proto udp to any port 53

ufw allow out to 95.163.252.67 proto tcp port 80,443

ufw allow in proto tcp from any to any port 80,443

echo "y" | ufw enable

echo "DONE"