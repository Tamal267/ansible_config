# Control Multiple Contest PCs from a Host Machine

This repository contains Ansible playbooks and scripts to configure contest PCs for university programming contests. Its main purpose is to easily restrict internet access on all contestant PCs during a contest and restore full access once the contest is over.

---

## Installation

Before running the playbooks, ensure you have Ansible installed on your administrator control machine.

### 1. Install Ansible

On Debian/Ubuntu-based systems:
```bash
sudo apt update
sudo apt install -y ansible
```

### 2. Configure Target PCs (Inventory)

Update the `inventory.ini` file with the hostnames or IP addresses of the contest PCs:
```ini
[lab]
pc1 ansible_host=192.168.122.161
pc2 ansible_host=192.168.122.27

[lab:vars]
ansible_user=admin
```
Ensure you have SSH access to the `ansible_user` (e.g., `admin`) on all target PCs. It is recommended to distribute your SSH public key to the target PCs for passwordless authentication.

---

## Run Commands

Run the playbooks from the root of this repository.

### Test Connectivity (Ping)

To test connectivity to all target PCs defined in the inventory, run:
```bash
ansible lab -m ping -i inventory.ini
```

### Block Internet Access (Start Contest Mode)

To restrict internet access on all contest PCs, run:
```bash
ansible-playbook -i inventory.ini -K site_block.yml
```
> **Note:** The `--ask-become-pass` (or `-K`) flag will prompt you for the privilege escalation (`sudo`) password on the remote machines. If you have passwordless sudo configured on the target PCs, you can omit this flag.

### Run playbook on specific PC

To run playbook on specific PC, use the `-l` flag:
```bash
ansible-playbook -i inventory.ini -K site_block.yml -l pc1
```
Or for multiple PCs:
```bash
ansible-playbook -i inventory.ini -K site_block.yml -l pc1,pc2
```
> **Note:** The `-l` (or `--limit`) flag will only run the playbook on the specified PC(s).

### Upgrade Target PCs

To update and upgrade packages on all target PCs, run:
```bash
ansible-playbook -i inventory.ini -K upgrade.yml
```

---
