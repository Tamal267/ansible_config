#!/usr/bin/env bash

set -euo pipefail

INVENTORY="inventory.ini"
PLAYBOOK="change_password.yml"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <USERNAME> <NEW_PASSWORD> [BECOME_PASSWORD]"
    echo ""
    echo "Examples:"
    echo "  $0 contest MyPassword123"
    echo "  $0 mcc SecretPassword456 myadminpass"
    exit 1
fi

USERNAME="$1"
NEW_PASSWORD="$2"
BECOME_PASS="${3:-}"

if [[ ! -f "$PLAYBOOK" ]]; then
    echo "Error: Playbook '$PLAYBOOK' not found in current directory." >&2
    exit 1
fi

if [[ -n "$BECOME_PASS" ]]; then
    ansible-playbook -i "$INVENTORY" "$PLAYBOOK" \
        -e "username=$USERNAME new_password=$NEW_PASSWORD ansible_sudo_pass=$BECOME_PASS"
else
    ansible-playbook -i "$INVENTORY" -K "$PLAYBOOK" \
        -e "username=$USERNAME new_password=$NEW_PASSWORD"
fi
