# Remote Username Changer

**Securely rename a user account on a remote Debian/Ubuntu system via SSH**

This Bash script allows you to change a username (including home directory) on a remote Linux server without physical access. It uses a temporary root password to enable root SSH login briefly, performs the rename, and then disables root login again and removes the temporary password.

**Important:** This is a **high-risk operation**. Always create a full backup (e.g. Timeshift, rsync, LVM snapshot) before running!

## Features

- Pre-checks: SSH login + sudo rights validation
- Temporary root password activation (via `chpasswd`)
- Temporary `PermitRootLogin yes` insertion at the top of `sshd_config`
- Safe cleanup: removes temporary lines and root password
- Final automatic login test with new username
- Clear error messages and safety warnings
- Uses `-q -t` SSH flags for stability (tested on Debian 12)

## Requirements

**Local machine (where you run the script):**
- `sshpass` installed  
  ```bash
  sudo apt update && sudo apt install sshpass
