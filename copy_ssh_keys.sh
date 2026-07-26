#!/usr/bin/env bash

set -euo pipefail

# Default values
INVENTORY_FILE="inventory.ini"
KEY_FILE=""
DEFAULT_USER="admin"
ASK_PASS=false
SSH_PASS=""

usage() {
    echo "Usage: $0 [-i INVENTORY_FILE] [-k KEY_FILE] [-u DEFAULT_USER] [-p] [-P PASSWORD]"
    echo ""
    echo "Copies SSH public key to all hosts listed in the Ansible inventory file."
    echo ""
    echo "Options:"
    echo "  -i INVENTORY_FILE  Path to Ansible inventory file (default: inventory.ini)"
    echo "  -k KEY_FILE        Path to SSH private/public key (default: ~/.ssh/ansible or from inventory)"
    echo "  -u DEFAULT_USER    Default SSH username if not defined in inventory (default: admin)"
    echo "  -p, --ask-pass     Prompt once for SSH password and auto-fill for all PCs (requires sshpass)"
    echo "  -P PASSWORD        Provide SSH password on command line (requires sshpass)"
    echo "  -h, --help         Show this help message"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)
            INVENTORY_FILE="$2"
            shift 2
            ;;
        -k)
            KEY_FILE="$2"
            shift 2
            ;;
        -u)
            DEFAULT_USER="$2"
            shift 2
            ;;
        -p|--ask-pass)
            ASK_PASS=true
            shift 1
            ;;
        -P)
            SSH_PASS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "Error: Inventory file '$INVENTORY_FILE' not found." >&2
    exit 1
fi

# Check for sshpass requirement if password mode is used
if [[ "$ASK_PASS" = true || -n "$SSH_PASS" ]]; then
    if ! command -v sshpass >/dev/null 2>&1; then
        echo "Error: 'sshpass' is required to automatically send the SSH password." >&2
        echo "" >&2
        echo "Please install sshpass on your control machine:" >&2
        echo "  Debian/Ubuntu: sudo apt update && sudo apt install -y sshpass" >&2
        echo "  Arch Linux:    sudo pacman -S sshpass" >&2
        exit 1
    fi
fi

# Prompt securely for password if -p / --ask-pass flag was specified
if [[ "$ASK_PASS" = true && -z "$SSH_PASS" ]]; then
    read -r -s -p "Enter SSH password for remote target PCs: " SSH_PASS
    echo ""
fi

# Arrays to hold host info
declare -a HOSTS=()
declare -a USERS=()

GLOBAL_USER=""
GLOBAL_KEY=""
CURRENT_SECTION=""

# Parse global vars and collect hosts
while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip leading/trailing whitespace
    line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Ignore empty lines and comments
    if [[ -z "$line" || "$line" =~ ^[#\;] ]]; then
        continue
    fi

    # Detect section header [section]
    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
        CURRENT_SECTION="${BASH_REMATCH[1]}"
        continue
    fi

    # Parse [all:vars] or [group:vars]
    if [[ "$CURRENT_SECTION" =~ :vars$ ]]; then
        if [[ "$line" =~ ^ansible_user=(.*)$ ]]; then
            GLOBAL_USER="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^ansible_ssh_private_key_file=(.*)$ ]]; then
            GLOBAL_KEY="${BASH_REMATCH[1]}"
        fi
        continue
    fi

    # Skip :children sections
    if [[ "$CURRENT_SECTION" =~ :children$ ]]; then
        continue
    fi

    # Process host entry line in a normal group
    if [[ -n "$CURRENT_SECTION" ]]; then
        HOST=""
        USER=""

        # Check for ansible_host=...
        if [[ "$line" =~ ansible_host=([^[:space:]]+) ]]; then
            HOST="${BASH_REMATCH[1]}"
        else
            # Use first token as host
            HOST=$(echo "$line" | awk '{print $1}')
        fi

        # Check for inline ansible_user=...
        if [[ "$line" =~ ansible_user=([^[:space:]]+) ]]; then
            USER="${BASH_REMATCH[1]}"
        fi

        if [[ -n "$HOST" ]]; then
            HOSTS+=("$HOST")
            USERS+=("$USER")
        fi
    fi
done < "$INVENTORY_FILE"

if [[ ${#HOSTS[@]} -eq 0 ]]; then
    echo "No target hosts found in '$INVENTORY_FILE'."
    exit 0
fi

# Determine key file to use
if [[ -z "$KEY_FILE" ]]; then
    if [[ -n "$GLOBAL_KEY" ]]; then
        KEY_FILE="$GLOBAL_KEY"
    else
        KEY_FILE="~/.ssh/ansible"
    fi
fi

# Expand tilde in key path
KEY_FILE="${KEY_FILE/#\~/$HOME}"

# Check key existence
if [[ "$KEY_FILE" != *.pub ]] && [[ -f "${KEY_FILE}.pub" ]]; then
    KEY_FILE_PUB="${KEY_FILE}.pub"
else
    KEY_FILE_PUB="$KEY_FILE"
fi

if [[ ! -f "$KEY_FILE_PUB" && ! -f "$KEY_FILE" ]]; then
    echo "Warning: Key file '$KEY_FILE' (or '$KEY_FILE_PUB') does not exist." >&2
    echo "Please generate an SSH key first, e.g.: ssh-keygen -t ed25519 -C ansible -f ~/.ssh/ansible" >&2
    exit 1
fi

echo "=================================================="
echo "Ansible SSH Key Distributor"
echo "Inventory: $INVENTORY_FILE"
echo "Key file:  $KEY_FILE"
if [[ -n "$SSH_PASS" ]]; then
    echo "Password:  [Single Password Mode Enabled]"
fi
echo "Found ${#HOSTS[@]} host(s) to process."
echo "=================================================="
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

# Auto-accept host fingerprint prompts
SSH_OPTS=(-o "StrictHostKeyChecking=accept-new")

for i in "${!HOSTS[@]}"; do
    HOST="${HOSTS[$i]}"
    HOST_USER="${USERS[$i]}"

    # Fallback host user to global user or default user
    if [[ -z "$HOST_USER" ]]; then
        if [[ -n "$GLOBAL_USER" ]]; then
            HOST_USER="$GLOBAL_USER"
        else
            HOST_USER="$DEFAULT_USER"
        fi
    fi

    TARGET="${HOST_USER}@${HOST}"
    echo "--------------------------------------------------"
    echo "[$((i+1))/${#HOSTS[@]}] Copying SSH key to $TARGET..."
    echo "--------------------------------------------------"

    if [[ -n "$SSH_PASS" ]]; then
        if SSHPASS="$SSH_PASS" sshpass -e ssh-copy-id "${SSH_OPTS[@]}" -i "$KEY_FILE" "$TARGET"; then
            echo "Successfully copied key to $TARGET"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "Failed to copy key to $TARGET" >&2
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        if ssh-copy-id "${SSH_OPTS[@]}" -i "$KEY_FILE" "$TARGET"; then
            echo "Successfully copied key to $TARGET"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "Failed to copy key to $TARGET" >&2
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
    echo ""
done

echo "=================================================="
echo "Summary: $SUCCESS_COUNT succeeded, $FAIL_COUNT failed out of ${#HOSTS[@]} host(s)."
echo "=================================================="
