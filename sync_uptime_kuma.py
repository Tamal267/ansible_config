#!/usr/bin/env python3

import argparse
import configparser
import getpass
import sys
from pathlib import Path

from uptime_kuma_api import UptimeKumaApi, MonitorType


# ---------------------------------------------------------
# Configuration
# ---------------------------------------------------------

DEFAULT_KUMA_URL = "http://127.0.0.1:3001"
DEFAULT_INVENTORY = "inventory.ini"
DEFAULT_PORT = 22
DEFAULT_INTERVAL = 30
DEFAULT_RETRY_INTERVAL = 20
DEFAULT_MAX_RETRIES = 3


# These are Ansible meta-groups and should NOT become
# Uptime Kuma monitor groups.
IGNORED_GROUPS = {
    "all",
    "ungrouped",
}


# ---------------------------------------------------------
# Parse Ansible inventory.ini
# ---------------------------------------------------------

def parse_inventory(inventory_path):
    """
    Parse a simple INI-style Ansible inventory.

    Returns:

    [
        {
            "name": "pc1",
            "host": "192.168.122.201",
            "group": "lab1"
        },
        ...
    ]
    """

    config = configparser.ConfigParser(
        allow_no_value=True,
        delimiters=(" ", "\t"),
        comment_prefixes=("#", ";"),
        strict=False,
    )

    # ConfigParser expects sections in INI files.
    # We don't actually use it directly because Ansible
    # inventory syntax is not standard INI.
    del config

    monitors = []

    current_group = None

    inventory_path = Path(inventory_path)

    if not inventory_path.exists():
        raise FileNotFoundError(
            f"Inventory file not found: {inventory_path}"
        )

    with inventory_path.open("r", encoding="utf-8") as file:
        for raw_line in file:
            line = raw_line.strip()

            # Ignore blank lines
            if not line:
                continue

            # Ignore comments
            if line.startswith("#") or line.startswith(";"):
                continue

            # Detect group
            if line.startswith("[") and line.endswith("]"):
                current_group = line[1:-1].strip()

                # Ignore meta groups such as [all:vars]
                if ":" in current_group:
                    current_group = None

                continue

            # Ignore hosts outside a normal group
            if not current_group:
                continue

            # Ignore meta groups
            if current_group in IGNORED_GROUPS:
                continue

            # Ignore group children / variables
            if ":" in current_group:
                continue

            # Split:
            #
            # pc2 ansible_host=192.168.122.215
            #
            # into:
            #
            # pc2
            # ansible_host=192.168.122.215

            parts = line.split()

            if not parts:
                continue

            hostname = parts[0]

            variables = {}

            for item in parts[1:]:
                if "=" not in item:
                    continue

                key, value = item.split("=", 1)
                variables[key] = value

            # Get ansible_host.
            # If it doesn't exist, use the inventory hostname.
            host = variables.get("ansible_host", hostname)

            # Ignore localhost if present
            if hostname == "localhost":
                continue

            monitor = {
                "name": hostname,
                "host": host,
                "group": current_group,
            }

            monitors.append(monitor)

    return monitors


# ---------------------------------------------------------
# Remove duplicate hosts from inventory
# ---------------------------------------------------------

def deduplicate_hosts(monitors):
    """
    A PC can potentially appear in multiple Ansible groups.

    We don't want to create duplicate Uptime Kuma monitors
    for the same hostname/IP combination.
    """

    unique = {}

    for monitor in monitors:

        key = (
            monitor["name"],
            monitor["host"],
        )

        if key not in unique:
            unique[key] = monitor

    return list(unique.values())


# ---------------------------------------------------------
# Create monitor name
# ---------------------------------------------------------

def build_monitor_name(monitor):
    """
    Example:

    lab1 + pc1
        -> lab1/pc1

    mmg + mmg01
        -> mmg/mmg01
    """

    return f"{monitor['group']}/{monitor['name']}"


# ---------------------------------------------------------
# Synchronize with Uptime Kuma
# ---------------------------------------------------------

def sync_monitors(
    kuma_url,
    username,
    password,
    inventory_path,
    port,
    interval,
    retry_interval,
    max_retries,
):

    print()
    print("=" * 60)
    print("Uptime Kuma Monitor Synchronization")
    print("=" * 60)

    print(f"Inventory : {inventory_path}")
    print(f"Kuma URL  : {kuma_url}")
    print(f"Port      : {port}")
    print()

    # -----------------------------------------------------
    # Read inventory
    # -----------------------------------------------------

    monitors = parse_inventory(inventory_path)

    monitors = deduplicate_hosts(monitors)

    if not monitors:
        print("No hosts found in inventory.")
        return

    print(f"Found {len(monitors)} hosts in inventory.")
    print()

    # -----------------------------------------------------
    # Connect to Uptime Kuma
    # -----------------------------------------------------

    print("Connecting to Uptime Kuma...")

    with UptimeKumaApi(kuma_url) as api:

        api.login(username, password)

        print("Successfully logged in.")
        print()

        # -------------------------------------------------
        # Get existing monitors
        # -------------------------------------------------

        print("Reading existing Uptime Kuma monitors...")

        existing_monitors = api.get_monitors()

        # Create lookup dictionaries.
        #
        # We check both:
        #
        # 1. Monitor name
        # 2. Hostname + port
        #
        # This prevents accidental duplicate monitors.

        existing_by_name = {}

        existing_by_target = {}

        for existing in existing_monitors:

            existing_name = existing.get("name")

            existing_hostname = existing.get("hostname")

            existing_port = existing.get("port")

            if existing_name:
                existing_by_name[existing_name] = existing

            if existing_hostname and existing_port:
                target_key = (
                    str(existing_hostname),
                    int(existing_port),
                )

                existing_by_target[target_key] = existing

        print(
            f"Found {len(existing_monitors)} existing monitors."
        )

        print()
        print("-" * 60)

        # -------------------------------------------------
        # Create missing monitors
        # -------------------------------------------------

        created = 0
        skipped = 0

        for monitor in monitors:

            monitor_name = build_monitor_name(monitor)

            hostname = monitor["host"]

            target_key = (
                str(hostname),
                int(port),
            )

            print(
                f"Checking: {monitor_name} "
                f"({hostname}:{port})"
            )

            # -------------------------------------------------
            # Duplicate check 1:
            # Same monitor name
            # -------------------------------------------------

            if monitor_name in existing_by_name:

                print(
                    f"  SKIP: Monitor already exists "
                    f"with name '{monitor_name}'"
                )

                skipped += 1

                continue

            # -------------------------------------------------
            # Duplicate check 2:
            # Same host + port
            # -------------------------------------------------

            if target_key in existing_by_target:

                existing = existing_by_target[target_key]

                print(
                    f"  SKIP: Target already monitored as "
                    f"'{existing.get('name')}'"
                )

                skipped += 1

                continue

            # -------------------------------------------------
            # Create new monitor
            # -------------------------------------------------

            print("  CREATE: Adding TCP monitor...")

            result = api.add_monitor(
                type=MonitorType.PORT,
                name=monitor_name,
                hostname=hostname,
                port=port,
                interval=interval,
                retryInterval=retry_interval,
                maxretries=max_retries,
            )

            print(
                f"  OK: Created monitor "
                f"(ID: {result.get('monitorId')})"
            )

            created += 1

            # Add to our local lookup tables.
            # This prevents duplicates even within
            # the same script execution.

            new_monitor = {
                "id": result.get("monitorId"),
                "name": monitor_name,
                "hostname": hostname,
                "port": port,
            }

            existing_by_name[monitor_name] = new_monitor
            existing_by_target[target_key] = new_monitor

        # -------------------------------------------------
        # Summary
        # -------------------------------------------------

        print()
        print("=" * 60)
        print("Synchronization Complete")
        print("=" * 60)

        print(f"Inventory hosts : {len(monitors)}")
        print(f"Created         : {created}")
        print(f"Skipped         : {skipped}")
        print()


# ---------------------------------------------------------
# Main
# ---------------------------------------------------------

def main():

    parser = argparse.ArgumentParser(
        description=(
            "Synchronize Ansible inventory hosts "
            "with Uptime Kuma TCP monitors."
        )
    )

    parser.add_argument(
        "-i",
        "--inventory",
        default=DEFAULT_INVENTORY,
        help="Path to Ansible inventory.ini",
    )

    parser.add_argument(
        "--kuma-url",
        default=DEFAULT_KUMA_URL,
        help="Uptime Kuma URL",
    )

    parser.add_argument(
        "--username",
        required=True,
        help="Uptime Kuma username",
    )

    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_PORT,
        help="TCP port to monitor",
    )

    parser.add_argument(
        "--interval",
        type=int,
        default=DEFAULT_INTERVAL,
        help="Monitor interval in seconds",
    )

    parser.add_argument(
        "--retry-interval",
        type=int,
        default=DEFAULT_RETRY_INTERVAL,
        help="Retry interval in seconds",
    )

    parser.add_argument(
        "--max-retries",
        type=int,
        default=DEFAULT_MAX_RETRIES,
        help="Maximum retries",
    )

    args = parser.parse_args()

    password = getpass.getpass(
        "Uptime Kuma password: "
    )

    try:

        sync_monitors(
            kuma_url=args.kuma_url,
            username=args.username,
            password=password,
            inventory_path=args.inventory,
            port=args.port,
            interval=args.interval,
            retry_interval=args.retry_interval,
            max_retries=args.max_retries,
        )

    except KeyboardInterrupt:

        print("\nCancelled.")

        sys.exit(1)

    except Exception as error:

        print()
        print("ERROR:")
        print(error)

        sys.exit(1)


if __name__ == "__main__":
    main()