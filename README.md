# ssh-rename-user
Remote Username Changer Securely renames a user on a remote Debian/Ubuntu system via SSH. Temporarily enables root login (password), changes username &amp; home dir, then disables root access and removes temp root password. Includes pre-checks (SSH + sudo), final login test and safety warnings. Requires sshpass locally. 
