# Control Multiple Contest PCs from a Host Machine

This repository contains Ansible playbooks and scripts to configure contest PCs for university programming contests. Its main purpose is to configure and manage contestant PCs for programming contests.

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
   Run the helper script to copy your SSH public key to all PCs defined in `inventory.ini`:
   ```bash
   # Option A: Type password once for all PCs (requires sshpass)
   ./copy_ssh_keys.sh -p

   # Option B: Interactive (prompts password for each PC)
   ./copy_ssh_keys.sh
   ```
   *(Or manually for individual PCs: `ssh-copy-id -i ~/.ssh/ansible admin@<TARGET_IP>`)*

3. **Verify SSH Connection:**
   ```bash
   ssh -i ~/.ssh/ansible admin@192.168.122.153
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
ansible_user=admin
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

> **Warning:** Ensure all package installation and setup playbooks (`setup_contest_user.yml`, `start_screenshot.yml`, `upgrade.yml`) are executed **BEFORE** running `site_block.yml`. Blocking internet access first will prevent target PCs from reaching online package repositories (`apt`).

> **Important:** Before running `site_block.yml`, update `site_block.sh` (lines 21–22) with the IP address of your contest/judge server:
> ```bash
> ufw allow out to <YOUR_CONTEST_SERVER_IP> proto tcp port 80
> ufw allow out to <YOUR_CONTEST_SERVER_IP> proto tcp port 443
> ```

To restrict internet access on all contest PCs, run:
```bash
ansible-playbook -i inventory.ini -K site_block.yml
```
> **Note:** The `--ask-become-pass` (or `-K`) flag will prompt you for the privilege escalation (`sudo`) password on the remote machines. If you have passwordless sudo configured on the target PCs, you can omit this flag.

### Restore Internet Access (Unblock Contest Mode)

To restore full internet access on all contest PCs once the contest is over, run:
```bash
ansible-playbook -i inventory.ini -K site_unblock.yml
```

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

### Change User Password

To change the password for any user account across all target PCs:

```bash
# Usage via script wrapper:
./change_password.sh <USERNAME> <NEW_PASSWORD>

# Example:
./change_password.sh contest MyNewPassword123
```

Or directly via Ansible playbook:
```bash
ansible-playbook -i inventory.ini -K change_password.yml -e "username=contest new_password=MyNewPassword123"
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

### Synchronize System Date & Time (Offline / Restricted Network)

During a contest when internet access is blocked, target PCs cannot contact external NTP servers. To synchronize all target PCs to the exact date & time of the administrator host machine (and save the synced time to each PC's BIOS/RTC hardware clock):

```bash
ansible-playbook -i inventory.ini -K sync_time.yml
```

To set a specific custom date & time across all target PCs:
```bash
ansible-playbook -i inventory.ini -K sync_time.yml -e "target_time='2026-07-22 09:00:00'"
```

### Shut Down Target PCs

To safely power off all target PCs (or specific PCs/groups):

```bash
# Using script wrapper (interactive confirmation):
./shutdown.sh

# Target a specific host or group (e.g. pc1 or mmg):
./shutdown.sh -l pc1

# Skip confirmation prompt:
./shutdown.sh -y

# Directly via Ansible playbook:
ansible-playbook -i inventory.ini -K shutdown.yml
```

### Uninstall Custom Packages & Clean Locks / Temp Files

To uninstall packages installed by `custom-ubuntu` (Chrome, VS Code, Code::Blocks, Geany, Kate, Sublime, IntelliJ, PyCharm, Java 21, GCC/G++, PyPy3, etc.), remove installed text editors (including Nano), clear stale package manager locks, and remove temporary installer files—while preserving **SSH, Git, Curl, python3, Ansible configs, and `.ssh` keys**:

```bash
# Using script wrapper (interactive confirmation):
./cleanup_custom_packages.sh

# Target a specific host or group (e.g. pc1 or mmg):
./cleanup_custom_packages.sh -l pc1

# Skip confirmation prompt:
./cleanup_custom_packages.sh -y

# Directly via Ansible playbook:
ansible-playbook -i inventory.ini -K cleanup_custom_packages.yml
```

Editor cleanup covers common terminal editors (Nano, Vim including `vim-tiny`, Neovim, Emacs, Micro, Ed, and others), desktop editors (GNOME Text Editor, Gedit, Mousepad, Pluma, Xed, and others), and additional installed APT/Snap/Flatpak applications whose desktop entry declares `TextEditor` or `IDE`. Flatpak discovery includes the default system installation and existing per-user installations. Named custom Flatpak installations and arbitrary portable executables are outside this discovery. Unmanaged desktop entries are reported for manual removal. Local/devmode editor Snaps stop discovery because they cannot be restored from a store channel.

Before removing editors, cleanup saves a root-owned record at `/var/lib/ansible_config/editor-restore.json` on each target PC. The record retains previously discovered editors across repeated cleanup runs and includes Snap channels and Flatpak origins/branches. Keep that file for revert. Editor removal failures are fatal, so cleanup cannot silently ignore a failed editor uninstall. Browser packages are not selected by editor discovery; the original cleanup still removes Chrome and leaves other browsers such as Firefox alone. Autoremove is simulated first and skipped if it would remove a remaining common browser or desktop session package. This removes editor software, but does not enforce a browser-only kiosk or prevent installing/running portable programs.

### Restore Missing Software and Update Code::Blocks

Run the restore wrapper on the **Ansible control PC** to reinstall missing applications on the target PCs:

```bash
./restore_custom_packages.sh -l mmg_pc48

# Preview (vendor downloads and archive installations are skipped in check mode):
./restore_custom_packages.sh -l mmg_pc48 --check

# Install/update only Code::Blocks and its plugins:
./restore_custom_packages.sh -l mmg_pc48 --codeblocks-only

# All inventory hosts, without the wrapper confirmation:
./restore_custom_packages.sh -y
```

The wrapper prompts for the target sudo password through Ansible (`-K`). Target PCs need internet access; run `site_unblock.yml` first if internet access was blocked. Ubuntu amd64 is currently supported.

Existing APT packages are skipped. Missing packages from the cleanup list are installed with `state: present`, including the compiler/Python tools, Geany, Kate, Vim, LibreOffice, Remmina, Shotwell, and XTerm. Missing Chrome and VS Code use official vendor DEBs; missing Sublime Text uses its signed stable repository. The script also checks command launchers before installing those vendor applications, including Snap launchers.

Missing IntelliJ IDEA Community and PyCharm Community use JetBrains' available Community archives with vendor SHA256 verification, restoring `/opt/intellij`, `/opt/pycharm`, command links, and desktop entries. Existing launchers, recognized `/opt` installations, and Community Snap launchers are skipped. Java is left alone when `java` is available; otherwise Ubuntu's `openjdk-21-jdk` is installed. This restores a Java 21 toolchain, rather than recreating the removed Adoptium 21.0.4 directory.

**Only Code::Blocks is requested with `state: latest`**, together with `codeblocks-common` and `codeblocks-contrib`. Here, “latest” means the newest candidate from the target PC's configured APT repositories, which may be older than the latest upstream release. The installed package version is printed at the end. There is no full-system upgrade; APT may still update dependencies when required by an installation.

This is a software restore, not an exact rollback: original versions were not recorded by cleanup. Deleted user homes, preferences, custom ISO directories, and temporary files cannot be reconstructed. The removed `mock` account is not recreated. APT metadata is refreshed, and installation failures are reported instead of ignored.

Restore also reinstalls missing editors from the target's saved editor record, including Snap and Flatpak installations, while skipping installed ones. Their original repositories/store channels must remain available, and per-user Flatpak accounts must still exist. Without a record (for PCs cleaned by the older script), it installs Nano, Gedit, and GNOME Text Editor as defaults. The record tracks package identities, not original APT versions or deleted settings. Code::Blocks continues to use the latest configured APT candidate.

---

## Uptime Kuma Dashboard & Monitoring

Uptime Kuma is used to monitor real-time TCP connectivity (port 22) for all contest PCs from a central dashboard.

### 1. Install Docker & Run Uptime Kuma Container

On Debian/Ubuntu-based systems:
```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

On Arch Linux:
```bash
sudo pacman -Syu docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

Create a directory (e.g., `~/projects/uptime-kuma`) with `compose.yml`:
```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:2
    container_name: uptime-kuma
    restart: unless-stopped
    network_mode: "host"
    volumes:
      - ./uptime-kuma-data:/app/data
```

Start Uptime Kuma:
```bash
docker compose up -d
```
Navigate to `http://127.0.0.1:3001` in your browser and create your admin account (e.g. username `admin`).

### 2. Synchronize Ansible Inventory to Uptime Kuma

Automatically create/update monitors in Uptime Kuma for all target hosts defined in `inventory.ini`:

```bash
# Set up Python virtual environment & install requirements
python3 -m venv .venv
source .venv/bin/activate
pip install uptime-kuma-api

# Run synchronization script
./sync_uptime_kuma.py -i inventory.ini --username admin
```

---








