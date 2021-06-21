Restic Init
===========

## Requirements

  - [Arch Linux](https://archlinux.org)

### Getting started

Run `init.sh` and follow the prompts.

## Restoring Data

    # export $(grep -v "^#" /etc/restic/config | xargs)
    # restic mount <mount_path>

View the [Restic documentation](https://restic.readthedocs.io/en/stable/050_restore.html)
for additional instructions on restoring your data.
