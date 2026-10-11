#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="$SCRIPT_DIR/inventory.ini"
LIMIT=""
ASSUME_YES=false
EXTRA_ARGS=()

usage() {
    cat <<'EOF'
Usage: restore_custom_packages.sh [-i INVENTORY] [-l LIMIT] [-y] [--check] [--codeblocks-only]

Restore missing software, editors, calculators, image/video viewers; update Code::Blocks.
Installed applications are skipped except Code::Blocks. Prompts for sudo password.

  -i FILE             Inventory file
  -l HOST_OR_GROUP    Restrict target PCs
  -y, --yes           Skip confirmation
  --check             Ansible dry run (downloads/installations may be skipped)
  --codeblocks-only   Update only Code::Blocks
  -h, --help          Show help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|-l)
            if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                echo "Error: $1 requires a value." >&2
                exit 2
            fi
            if [[ "$1" == -i ]]; then INVENTORY="$2"; else LIMIT="$2"; fi
            shift 2
            ;;
        -y|--yes) ASSUME_YES=true; shift ;;
        --check) EXTRA_ARGS+=(--check); shift ;;
        --codeblocks-only) EXTRA_ARGS+=(--tags codeblocks); shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -f "$INVENTORY" ]] || { echo "Inventory not found: $INVENTORY" >&2; exit 1; }
command -v ansible-playbook >/dev/null || { echo "Install Ansible on this control PC first." >&2; exit 1; }

TARGET_DESC="all hosts in $INVENTORY"
[[ -z "$LIMIT" ]] || TARGET_DESC="$LIMIT in $INVENTORY"
if [[ "$ASSUME_YES" == false ]]; then
    echo "Restore missing software and update Code::Blocks on $TARGET_DESC."
    read -r -p "Continue? [y/N] " response
    case "$response" in y|Y|yes|YES|Yes) ;; *) echo "Restore canceled."; exit 0 ;; esac
fi

CMD=(ansible-playbook -i "$INVENTORY" -K "$SCRIPT_DIR/restore_custom_packages.yml")
[[ -z "$LIMIT" ]] || CMD+=(-l "$LIMIT")
CMD+=("${EXTRA_ARGS[@]}")
exec "${CMD[@]}"
