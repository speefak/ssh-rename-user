 =============================================================================
 Script:       Remote Username Changer
 Description:  Changes a username on a remote Debian-like system via SSH.
               Temporarily enables root login with password, renames the user,
               then disables root login again and removes the temporary root password.

 Requirements:
   - Local: sshpass installed (sudo apt install sshpass)
   - Remote: sudo-capable user with known password
   - Remote: PasswordAuthentication yes in sshd_config
   - Remote: Debian/Ubuntu-like system with systemctl or service

 Security Warning:
   - This script temporarily enables root login with password → security risk!
   - Temporary root password exists only during execution.
   - ALWAYS MAKE A BACKUP before running!
   - Test thoroughly in a virtual machine first!

 SSH Terminal Allocation Notes (-t / -tt)
 =============================================================================
 Why -t or -tt is used:
   -t / -tt forces allocation of a pseudo-terminal (pty) on the remote side.
   Required because sudo and passwd commands inside Here-Documents (<< EOF)
   often expect a terminal environment.

 Observed behavior in this script:
   - -t (single)         → usually works reliably in this setup
   - -tt (double)        → forces pty allocation more aggressively,
                            but can cause hangs / connection failures
                            with some sshd configurations or Here-Document usage
   - Recommendation here: Use -q -t    (quiet + single force)
                            → suppresses "Pseudo-terminal will not be allocated"
                              warning and provides stable behavior

 If you ever see:
   sudo: sorry, you must have a tty to run sudo
   → then try switching to -tt in the affected block only

 Current setting in this script: -q -t
 =============================================================================
