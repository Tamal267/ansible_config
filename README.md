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

On Arch Linux:
```bash
sudo pacman -S ansible
```

### 2. Set Up SSH Key Pair (Passwordless Authentication)

Generate an SSH key pair for Ansible and copy the public key to all target machines:

1. **Generate SSH Key Pair:**
   ```bash
   ssh-keygen -t ed25519 -C ansible
   ```
   *(Save the key file as `~/.ssh/ansible` when prompted, or pass `-f ~/.ssh/ansible`)*

2. **Copy Public Key to Target PCs:**
   ```bash
   ssh-copy-id -i ~/.ssh/ansible mcc@<TARGET_IP>
   ```
   *Example:*
   ```bash
   ssh-copy-id -i ~/.ssh/ansible mcc@192.168.122.153
   ssh-copy-id -i ~/.ssh/ansible mcc@192.168.122.215
   ```

3. **Verify SSH Connection:**
   ```bash
   ssh -i ~/.ssh/ansible mcc@192.168.122.153
   ```

### 3. Configure Target PCs (Inventory)

Update the `inventory.ini` file with the hostnames or IP addresses of the contest PCs, the remote user, and the SSH private key path:
```ini
[lab1]
pc1 ansible_host=192.168.122.153

[lab2]
pc2 ansible_host=192.168.122.215

[all:children]
lab1
lab2

[all:vars]
ansible_user=mcc
ansible_ssh_private_key_file=~/.ssh/ansible
```

---

## Run Commands

Run the playbooks from the root of this repository.

### Test Connectivity (Ping)

To test connectivity to all target PCs defined in the inventory, run:
```bash
ansible all -m ping -i inventory.ini
```
Or to test a specific group (e.g., `lab1`):
```bash
ansible lab1 -m ping -i inventory.ini
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

### Create Contest User & Deploy Editor Configurations (Code::Blocks, VS Code, .vimrc)

To create the non-sudo `contest` user (with `/bin/bash` shell and home directory) and copy Code::Blocks, VS Code, and `.vimrc` configurations:
```bash
ansible-playbook -i inventory.ini -K setup_contest_user.yml
```

To specify a custom username (instead of default `contest`), pass `-e "username=your_username"`:
```bash
ansible-playbook -i inventory.ini -K setup_contest_user.yml -e "username=contest2"
```

#### How to Generate Password Hashes

The `setup_contest_user.yml` playbook requires an encrypted SHA-512 password hash. To change the user password or generate a new hash, run:

```bash
openssl passwd -6 "your_password"
```
*(Or using `mkpasswd`: `mkpasswd -m sha-512 "your_password"`)*

Copy the output string starting with `$6$...` and update the `password` field in `setup_contest_user.yml`.

### Remove Contest User

To remove the default `contest` user account and completely delete their home directory on all target PCs:
```bash
ansible-playbook -i inventory.ini -K remove_contest_user.yml
```

To remove a custom username:
```bash
ansible-playbook -i inventory.ini -K remove_contest_user.yml -e "username=contest2"
```

### Screenshot Monitoring & Systemd Service Integration

Monitoring is managed natively via a systemd service (`screenshot-daemon.service`) for maximum reliability across 80+ PCs (auto-restarts on crash or system reboot). Files are protected with Linux Sticky Bit (`chmod 1777 /var/screenshots/`) so contestants cannot modify or delete any screenshots or videos.

To install, enable, and start screenshot monitoring on all target PCs:
```bash
ansible-playbook -i inventory.ini -K start_screenshot.yml
```

To stop monitoring and compile all captured frames into a permanent MP4 video (`/var/screenshots/contest_session_latest.mp4`):
```bash
ansible-playbook -i inventory.ini -K stop_screenshot.yml
```

---






