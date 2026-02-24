#!/usr/bin/env bash
# =============================================================================
# Script:       Remote Username Changer
# Version:      0.4
# Date:         2026-02-24
# Author:       [Your Name / Handle]
# Description:  Changes a username on a remote Debian-like system via SSH.
#               Temporarily enables root login with password, renames the user,
#               then disables root login again and removes the temporary root password.
#
# Requirements:
#   - Local: sshpass installed (sudo apt install sshpass)
#   - Remote: sudo-capable user with known password
#   - Remote: PasswordAuthentication yes in sshd_config
#   - Remote: Debian/Ubuntu-like system with systemctl or service
#
# Security Warning:
#   - This script temporarily enables root login with password → security risk!
#   - Temporary root password exists only during execution.
#   - ALWAYS MAKE A BACKUP before running!
#   - Test thoroughly in a virtual machine first!
#
# Usage:
#   ./change_username.sh
#   (defaults are pre-filled and editable)
#
# =============================================================================

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Input section
# ──────────────────────────────────────────────────────────────────────────────

DEFAULT_HOST="192.168.1.123"
DEFAULT_OLD_USER="user"
DEFAULT_NEW_USER="speefak"
DEFAULT_OLD_PASS="userpassword"

# Note: read -i only works together with -e (makes input editable)
# For password field (-s) the default value is still not visible!

echo "Press Enter to accept the pre-filled default value."
echo

read -e -i "$DEFAULT_HOST"   -p "Target host (IP or domain)      : " HOST
read -e -i "$DEFAULT_OLD_USER" -p "Old username                    : " OLD_USER
read -e -i "$DEFAULT_NEW_USER" -p "New username                    : " NEW_USER

# Password field: default is shown (but hidden), editable
# Press Enter → DEFAULT_OLD_PASS will be used
read -e -i "$DEFAULT_OLD_PASS" -p "Password for $OLD_USER (sudo capable): " OLD_PASS
echo


TMP_ROOT_PASS="tmproot"

echo
echo "Temporary root password will be set to '$TMP_ROOT_PASS' and removed at the end."
echo

# ──────────────────────────────────────────────────────────────────────────────
# Step 0: Set temporary root password as normal user
# ──────────────────────────────────────────────────────────────────────────────

echo "→ Setting temporary root password '$TMP_ROOT_PASS' ..."

sshpass -p "$OLD_PASS" ssh -t -o StrictHostKeyChecking=no "$OLD_USER@$HOST" << EOF || { echo "Failed to set root password!"; exit 1; }

  echo "$OLD_PASS" | sudo -S true 2>/dev/null || { echo "Wrong sudo password?"; exit 1; }

  echo "$OLD_PASS" | sudo -S passwd root <<EOP
$TMP_ROOT_PASS
$TMP_ROOT_PASS
EOP

  echo "Temporary root password set."

EOF

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Temporarily enable root login via SSH (as normal user)
# ──────────────────────────────────────────────────────────────────────────────

echo "→ Enabling PermitRootLogin yes ..."

sshpass -p "$OLD_PASS" ssh -t -o StrictHostKeyChecking=no "$OLD_USER@$HOST" << EOF || { echo "Failed to enable root SSH login!"; exit 1; }


  # add marker and configline at top of config file because first obtained value will be used
  echo "$OLD_PASS" | sudo -S sed -i '1i# TEMP_ENABLE_ROOT_LOGIN\nPermitRootLogin yes' /etc/ssh/sshd_config

  echo "$OLD_PASS" | sudo -S systemctl restart ssh || sudo -S service ssh restart

  echo "Root SSH login temporarily enabled."

EOF

sleep 2

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Connect as root → change username, disable root SSH + remove temp password
# ──────────────────────────────────────────────────────────────────────────────

echo "→ Connecting as root@$HOST and changing username ..."

sshpass -p "$TMP_ROOT_PASS" ssh -t -o StrictHostKeyChecking=no "root@$HOST" << EOF || { echo "Root login failed – root access remains enabled!"; exit 1; }

  echo "→ Changing $OLD_USER → $NEW_USER"

  pkill -u $OLD_USER || true

  usermod  -l $NEW_USER $OLD_USER
  usermod  -d /home/$NEW_USER -m $NEW_USER
  groupmod -n $NEW_USER $OLD_USER

  mv /var/mail/$OLD_USER     /var/mail/$NEW_USER     2>/dev/null || true
  mv /var/spool/cron/crontabs/$OLD_USER /var/spool/cron/crontabs/$NEW_USER 2>/dev/null || true

  chown -R $NEW_USER:$NEW_USER /home/$NEW_USER

  echo "→ Username changed."

  echo "→ Disabling root SSH + removing temporary root password ..."

  # Remove the temporary lines – e.g. everything from the marker to the next line
  echo "$OLD_PASS" | sudo -S sed -i '/# TEMP_ENABLE_ROOT_LOGIN/,+1d' /etc/ssh/sshd_config

  systemctl restart ssh || sudo -S service ssh restart

  passwd -d root

  echo "Root SSH disabled & temporary root password removed."

EOF

echo
echo "Done!"
echo "New user: ssh $NEW_USER@$HOST"
echo "Thoroughly test sudo, home directory, programs, .ssh etc.!"

