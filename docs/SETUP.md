# Setup Guide

This document explains how to set up the encrypted media infrastructure for the Theatre project.

## Encrypted Media Layout

The Theatre project uses gocryptfs to provide transparent encryption for media files. This ensures that all media content is stored encrypted at rest while being accessible to Jellyfin when mounted.

### Directory Structure

| Path | Purpose |
|------|---------|
| `/mnt/disks/media/.library_encrypted` | Encrypted backing directory (contains encrypted files) |
| `/srv/library_clear` | Decrypted mount point (where Jellyfin reads media) |

### First-Time Setup

Before using the encrypted storage, you must initialize gocryptfs. This only needs to be done once.

#### 1. Create the Directories

```bash
# Create the encrypted backing directory
sudo mkdir -p /mnt/disks/media/.library_encrypted

# Create the decrypted mount point
sudo mkdir -p /srv/library_clear
```

#### 2. Initialize gocryptfs

Run the following command to initialize the encrypted filesystem:

```bash
gocryptfs --init /mnt/disks/media/.library_encrypted
```

You will be prompted to create a password. **Store this password securely** — it is required to mount the encrypted filesystem.

This command creates the necessary configuration files inside the encrypted backing directory:
- `gocryptfs.conf` — encrypted master key and filesystem parameters/settings
- `gocryptfs.diriv` — directory IV for the root directory (each subdirectory gets its own)

### Mounting the Encrypted Filesystem

After initialization, mount the encrypted filesystem to access your media:

```bash
gocryptfs /mnt/disks/media/.library_encrypted /srv/library_clear
```

You will be prompted for the password you created during initialization.

Once mounted, files placed in `/srv/library_clear` will be transparently encrypted and stored in `/mnt/disks/media/.library_encrypted`.

### Unmounting

To unmount the encrypted filesystem:

```bash
fusermount -u /srv/library_clear
```

### Important Notes

- **Do not automate mounting** — The mount process requires manual password entry for security.
- **Backup your password** — Without the password, encrypted data cannot be recovered.
- **Backup gocryptfs.conf** — This file contains the encrypted master key and filesystem settings. Keep a secure backup.
- Files written to `/srv/library_clear` appear encrypted in `/mnt/disks/media/.library_encrypted`.
- Jellyfin accesses media through the decrypted mount at `/srv/library_clear`.

### Verifying the Mount

To verify the mount is active:

```bash
mount | grep library_clear
```

Or check if files are accessible:

```bash
ls -la /srv/library_clear
```
