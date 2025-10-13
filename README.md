Restic Init
===========

## Requirements

  - [Arch Linux](https://archlinux.org)
  - [Restic](https://restic.net)

### Getting started

  1. Run `make init`
  2. Edit `/etc/restic/config.env`
  3. Start the systemd timers

     ```
     systemctl enable --now restic-backup.timer restic-prune.timer
     ```
