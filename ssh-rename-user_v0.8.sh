#!/usr/bin/env bash

# =============================================================================
# Script:       Remote Username Changer
# Version:      0.8
# Date:         2026-02-24
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
# SSH Terminal Allocation Notes (-t / -tt)
# =============================================================================
# Why -t or -tt is used:
#   -t / -tt forces allocation of a pseudo-terminal (pty) on the remote side.
#   Required because sudo and passwd commands inside Here-Documents (<< EOF)
#   often expect a terminal environment.
#
# Observed behavior in this script:
#   - -t (single)         → usually works reliably in this setup
#   - -tt (double)        → forces pty allocation more aggressively,
#                            but can cause hangs / connection failures
#                            with some sshd configurations or Here-Document usage
#   - Recommendation here: Use -q -t    (quiet + single force)
#                            → suppresses "Pseudo-terminal will not be allocated"
#                              warning and provides stable behavior
#
# If you ever see:
#   sudo: sorry, you must have a tty to run sudo
#   → then try switching to -tt in the affected block only
#
# Current setting in this script: -q -t
# =============================================================================

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Check if sshpass is installed locally
# ──────────────────────────────────────────────────────────────────────────────

if ! command -v sshpass &> /dev/null; then
    echo "Error: sshpass is not installed on this machine."
    echo "Please install it first:"
    echo "  sudo apt update && sudo apt install sshpass"
    echo "or on other distributions:"
    echo "  sudo dnf install sshpass    # Fedora/RHEL"
    echo "  sudo pacman -S sshpass      # Arch"
    echo "  brew install sshpass        # macOS with Homebrew"
    exit 1
fi

echo "sshpass is installed. Continuing..."

# ──────────────────────────────────────────────────────────────────────────────
# Input section
# ──────────────────────────────────────────────────────────────────────────────

DEFAULT_HOST="192.168.1.123"
DEFAULT_OLD_USER="user"
DEFAULT_NEW_USER="speefak"
DEFAULT_OLD_PASS="userpassword"

echo "Press Enter to accept the pre-filled default value."
echo

read -e -i "$DEFAULT_HOST"   -p "Target host (IP or domain)      : " HOST
read -e -i "$DEFAULT_OLD_USER" -p "Old username                    : " OLD_USER
read -e -i "$DEFAULT_NEW_USER" -p "New username                    : " NEW_USER

read -e -i "$DEFAULT_OLD_PASS" -p "Password for $OLD_USER (sudo capable): " OLD_PASS
echo

TMP_ROOT_PASS="tmproot"

echo
echo "Temporary root password will be set to '$TMP_ROOT_PASS' and removed at the end."
echo


# ──────────────────────────────────────────────────────────────────────────────
# Early validation: Test SSH login and sudo with old user
# ──────────────────────────────────────────────────────────────────────────────

echo
echo "Validating connection and sudo rights with old user ($OLD_USER@$HOST)..."
echo

# check ssh old user login on host
echo -n "→ Testing remote SSH login "$OLD_USER@$HOST" ... "
if sshpass -p "$OLD_PASS" ssh -q -t -o ConnectTimeout=10 \
   -o StrictHostKeyChecking=no "$OLD_USER@$HOST" \
   "echo 'SSH login test OK'" >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    echo "Error: Cannot log in as $OLD_USER@$HOST with the provided password."
    echo "Please check:"
    echo "  • Host reachable?"
    echo "  • Password correct?"
    echo "  • PasswordAuthentication yes in sshd_config?"
    echo "  • Firewall / port 22 open?"
    exit 1
fi

# check sudo execution on remote host
echo -n "→ Testing sudo privileges on remote host ... "

if sshpass -p "$OLD_PASS" \
   ssh -q -o LogLevel=ERROR -o StrictHostKeyChecking=no "$OLD_USER@$HOST" \
   "echo '$OLD_PASS' | sudo -S true" >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    echo "Error: sudo test failed on remote host."
    exit 1
fi
echo "Pre-checks passed. Continuing with username change..."
echo


# ──────────────────────────────────────────────────────────────────────────────
# Step 0: Set temporary root password as normal user
# ──────────────────────────────────────────────────────────────────────────────

echo "→ Setting temporary root password '$TMP_ROOT_PASS' ..."

sshpass -p "$OLD_PASS" ssh -q -t -o StrictHostKeyChecking=no "$OLD_USER@$HOST" "bash -s" << EOF || { echo "Failed to set root password!"; exit 1; }

  echo "$OLD_PASS" | sudo -S true 2>/dev/null || { echo "Wrong sudo password?"; exit 1; }

  echo "$OLD_PASS" | sudo -S bash -c "echo 'root:$TMP_ROOT_PASS' | chpasswd"

  echo "Temporary root password set."

EOF

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Temporarily enable root login via SSH
# ──────────────────────────────────────────────────────────────────────────────

echo "→ Enabling PermitRootLogin yes ..."

sshpass -p "$OLD_PASS" ssh -q -t -o StrictHostKeyChecking=no "$OLD_USER@$HOST" "bash -s" << EOF || { echo "Failed to enable root SSH login!"; exit 1; }

  echo "$OLD_PASS" | sudo -S -p '' sed -i '1i# TEMP_ENABLE_ROOT_LOGIN\nPermitRootLogin yes' /etc/ssh/sshd_config
  echo "$OLD_PASS" | sudo -S -p '' systemctl restart ssh || sudo -S -p '' service ssh restart

  echo "Root SSH login temporarily enabled."

EOF

sleep 2

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Connect as root → change username, disable root SSH + remove temp password
# ──────────────────────────────────────────────────────────────────────────────

echo "→ Connecting as root@$HOST and changing username ..."

sshpass -p "$TMP_ROOT_PASS" ssh -q -t -o StrictHostKeyChecking=no "root@$HOST" "bash -s" << EOF || { echo "Root login failed – root access remains enabled!"; exit 1; }

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

  echo "$OLD_PASS" | sudo -S -p '' sed -i '/# TEMP_ENABLE_ROOT_LOGIN/,+1d' /etc/ssh/sshd_config

  systemctl restart ssh || sudo -S service ssh restart

  passwd -d root >/dev/null 2>&1

  echo "Root SSH disabled & temporary root password removed."

EOF

# ──────────────────────────────────────────────────────────────────────────────
# Final verification: Try to log in with the new username
# ──────────────────────────────────────────────────────────────────────────────

echo
echo "=============================================================================="
echo "Performing final test login with new user: $NEW_USER@$HOST"
echo "(using password: $OLD_PASS – assuming the password didn't change)"
echo

# Test login attempt (non-interactive, just to check if basic login is possible)
if sshpass -p "$OLD_PASS" ssh -o BatchMode=no -o ConnectTimeout=8 \
   -o StrictHostKeyChecking=no "$NEW_USER@$HOST" echo "Login test successful" 2>/dev/null; then

    echo "SUCCESS: Login with new username $NEW_USER succeeded!"
    echo "The change appears to have worked correctly."

else
    echo "WARNING: Automatic login test with new user FAILED."
    echo "Possible reasons:"
    echo "  • The password for the new user is different or not set"
    echo "  • PAM / sudoers configuration issues"
    echo "  • Home directory permissions wrong"
    echo "  • SSH key required now"
    echo
    echo "Please test manually:"
    echo "  ssh $NEW_USER@$HOST"
    echo "and verify sudo, home directory, .ssh etc."
fi

echo
echo "Done!"
echo "New user: ssh $NEW_USER@$HOST"
echo "Thoroughly test sudo, home directory, programs, .ssh etc.!"
echo "=============================================================================="
