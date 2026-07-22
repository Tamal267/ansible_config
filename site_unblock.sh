#!/bin/bash

set -eu

ufw --force reset
ufw default allow incoming
ufw default allow outgoing
ufw --force disable
echo "UNBLOCKED"