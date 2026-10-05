#!/usr/bin/env bash

set -euo pipefail

INVENTORY="inventory.ini"
PLAYBOOK="shutdown.yml"
LIMIT=""
ASSUME_YES=false
BECOME_PASS=""

usage() {
    echo "Usage: $0 [-i INVENTORY_FILE] [-l LIMIT] [-y] [-K BECOME_PASS] [-h]"
    echo ""
    echo "Shuts down target PCs defined in the Ansible inventory."
    echo ""
    echo "Options:"
    echo "  -i INVENTORY_FILE  Path to Ansible inventory file (default: inventory.ini)"
    echo "  -l LIMIT           Limit execution to specific host(s) or group(s) (e.g., pc1 or mmg)"
    echo "  -y, --yes          Skip confirmation prompt"
    echo "  -K BECOME_PASS     Provide sudo/become password directly"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 -l pc1"
    echo "  $0 -l mmg -y"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)
            INVENTORY="$2"
            shift 2
            ;;
        -l)
            LIMIT="$2"
            shift 2
            ;;
        -y|--yes)
            ASSUME_YES=true
            shift 1
            ;;
        -K)
            BECOME_PASS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

if [[ ! -f "$PLAYBOOK" ]]; then
    echo "Error: Playbook '$PLAYBOOK' not found in current directory." >&2
    exit 1
fi

if [[ ! -f "$INVENTORY" ]]; then
    echo "Error: Inventory file '$INVENTORY' not found." >&2
    exit 1
fi

TARGET_DESC="all hosts in '$INVENTORY'"
if [[ -n "$LIMIT" ]]; then
    TARGET_DESC="host(s)/group '$LIMIT' in '$INVENTORY'"
fi

if [[ "$ASSUME_YES" = false ]]; then
    read -r -p "Are you sure you want to shut down ${TARGET_DESC}? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            echo "Shutdown canceled."
            exit 0
            ;;
    esac
fi

CMD=(ansible-playbook -i "$INVENTORY" "$PLAYBOOK")

if [[ -n "$LIMIT" ]]; then
    CMD+=(-l "$LIMIT")
fi

if [[ -n "$BECOME_PASS" ]]; then
    CMD+=(-e "ansible_sudo_pass=$BECOME_PASS")
else
    CMD+=(-K)
fi

echo "Initiating shutdown for ${TARGET_DESC}..."
"${CMD[@]}"
