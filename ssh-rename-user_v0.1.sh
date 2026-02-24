#!/usr/bin/env bash

# Script: Remote Username ändern – mit temporärem Root-Passwort tmproot
#         (kein permanentes Root-Passwort nötig)
#
# Voraussetzungen:
# - Alter User (speefak) hat sudo-Rechte (Passwort erforderlich)
# - SSH-Passwort-Auth ist erlaubt (PasswordAuthentication yes)
# - Auf dem Ziel: Debian-ähnliches System mit sshd + sudo
# - Installiere lokal: sudo apt install sshpass
# - Backup!!! Das Script ist mächtig und gefährlich bei Tippfehlern
# - Teste zuerst in einer VM!!!

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Eingaben
# ──────────────────────────────────────────────────────────────────────────────

read -p "Ziel-Host (IP oder Domain): " HOST
read -p "Alter Username:               " OLD_USER
read -p "Neuer Username:               " NEW_USER
read -s -p "Passwort für $OLD_USER (sudo-fähig): " OLD_PASS
echo

TMP_ROOT_PASS="tmproot"

echo
echo "Temporäres Root-Passwort wird auf '$TMP_ROOT_PASS' gesetzt und am Ende gelöscht."
echo

# ──────────────────────────────────────────────────────────────────────────────
# Schritt 0: Als normaler User → temporäres Root-Passwort setzen
# ──────────────────────────────────────────────────────────────────────────────

echo "→ Setze temporäres Root-Passwort '$TMP_ROOT_PASS' ..."

sshpass -p "$OLD_PASS" ssh -t -o StrictHostKeyChecking=no "$OLD_USER@$HOST" << EOF || { echo "Fehler beim Setzen des Root-Passworts!"; exit 1; }

  echo "$OLD_PASS" | sudo -S true 2>/dev/null || { echo "Falsches sudo-Passwort?"; exit 1; }

  echo "$OLD_PASS" | sudo -S passwd root <<EOP
$TMP_ROOT_PASS
$TMP_ROOT_PASS
EOP

  echo "Temporäres Root-Passwort gesetzt."

EOF

# ──────────────────────────────────────────────────────────────────────────────
# Schritt 1: Root-SSH temporär erlauben (über normalen User)
# ──────────────────────────────────────────────────────────────────────────────

echo "→ Aktiviere PermitRootLogin yes ..."

sshpass -p "$OLD_PASS" ssh -t -o StrictHostKeyChecking=no "$OLD_USER@$HOST" << EOF || { echo "Fehler beim Aktivieren von Root-SSH!"; exit 1; }

  echo "$OLD_PASS" | sudo -S sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  echo "$OLD_PASS" | sudo -S grep -q '^PermitRootLogin yes' /etc/ssh/sshd_config || \
    echo "PermitRootLogin yes" | sudo -S tee -a /etc/ssh/sshd_config

  echo "$OLD_PASS" | sudo -S sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

  echo "$OLD_PASS" | sudo -S systemctl restart ssh || sudo -S service ssh restart

  echo "Root-SSH erlaubt (temporär)."

EOF

sleep 2

# ──────────────────────────────────────────────────────────────────────────────
# Schritt 2: Als root einloggen → Username ändern, Root-SSH deaktivieren + Root-Passwort löschen
# ──────────────────────────────────────────────────────────────────────────────

echo "→ Verbinde als root@$HOST und ändere Username ..."

sshpass -p "$TMP_ROOT_PASS" ssh -t -o StrictHostKeyChecking=no "root@$HOST" << EOF || { echo "Root-Login fehlgeschlagen – Root bleibt aktiviert!"; exit 1; }

  echo "→ Ändere $OLD_USER → $NEW_USER"

  pkill -u $OLD_USER || true

  usermod  -l $NEW_USER $OLD_USER
  usermod  -d /home/$NEW_USER -m $NEW_USER
  groupmod -n $NEW_USER $OLD_USER

  mv /var/mail/$OLD_USER     /var/mail/$NEW_USER     2>/dev/null || true
  mv /var/spool/cron/crontabs/$OLD_USER /var/spool/cron/crontabs/$NEW_USER 2>/dev/null || true

  chown -R $NEW_USER:$NEW_USER /home/$NEW_USER

  echo "→ Username geändert."

  echo "→ Deaktiviere Root-SSH + lösche temporäres Root-Passwort ..."

  sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

  systemctl restart ssh || sudo -S service ssh restart

  passwd -d root

  echo "Root-SSH deaktiviert & Root-Passwort gelöscht."

EOF

echo
echo "Fertig!"
echo "Neuer User: ssh $NEW_USER@$HOST"
echo "Teste sudo, Home-Verzeichnis, Programme, .ssh usw. gründlich!"
echo "Viel Erfolg!"
