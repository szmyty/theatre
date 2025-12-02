# gocryptfs Systemd Service

This document explains how to install and configure the systemd service for automatic gocryptfs mounting on boot.

## Overview

The `gocryptfs-mount.service` automatically mounts your encrypted media directory at system startup, making it available for Docker containers like Jellyfin before they start.

## Prerequisites

- gocryptfs installed on the system
- An initialized gocryptfs encrypted directory (see [SETUP.md](./SETUP.md))
- A password file containing the gocryptfs password
- FUSE configured to allow other users: `/etc/fuse.conf` must contain `user_allow_other`

## Installation

### 1. Configure FUSE

Ensure FUSE is configured to allow other users to access the mount. Edit `/etc/fuse.conf` and uncomment or add:

```bash
user_allow_other
```

This is required for Docker containers to access the decrypted mount.

### 2. Create the Password File

Create a secure password file that contains your gocryptfs password:

```bash
sudo mkdir -p /etc/gocryptfs
sudo touch /etc/gocryptfs/passfile
sudo chmod 600 /etc/gocryptfs/passfile
echo "your-gocryptfs-password" | sudo tee /etc/gocryptfs/passfile > /dev/null
```

> **Security Note:** Ensure the password file has restricted permissions (600) and is owned by root.

### 3. Create the Environment File

Create the environment file that configures the service:

```bash
sudo touch /etc/gocryptfs/gocryptfs.env
sudo chmod 600 /etc/gocryptfs/gocryptfs.env
```

Add the following content to `/etc/gocryptfs/gocryptfs.env`:

```bash
# Path to the encrypted backing directory
GOCRYPTFS_ENCRYPTED_DIR=/mnt/disks/media/.library_encrypted

# Path to the decrypted mount point
GOCRYPTFS_MOUNT_POINT=/srv/library_clear

# Path to the password file
GOCRYPTFS_PASSFILE=/etc/gocryptfs/passfile
```

Adjust the paths to match your setup.

### 4. Install the Service

Copy the systemd service file to the system directory:

```bash
sudo cp infrastructure/systemd/gocryptfs-mount.service /etc/systemd/system/
```

### 5. Enable and Start the Service

Enable the service to start on boot and start it immediately:

```bash
sudo systemctl enable --now gocryptfs-mount
```

## Usage

### Check Service Status

```bash
sudo systemctl status gocryptfs-mount
```

### Manually Stop the Mount

```bash
sudo systemctl stop gocryptfs-mount
```

### Manually Start the Mount

```bash
sudo systemctl start gocryptfs-mount
```

### View Service Logs

```bash
sudo journalctl -u gocryptfs-mount
```

## Configuration Options

The service uses the following environment variables from `/etc/gocryptfs/gocryptfs.env`:

| Variable | Description |
|----------|-------------|
| `GOCRYPTFS_ENCRYPTED_DIR` | Path to the encrypted backing directory |
| `GOCRYPTFS_MOUNT_POINT` | Path where the decrypted filesystem will be mounted |
| `GOCRYPTFS_PASSFILE` | Path to the file containing the gocryptfs password |

## Docker Integration

The service is configured to:

- Start after local filesystems are available (`After=local-fs.target`)
- Start before Docker (`Before=docker.service`)
- Use `-allow_other` flag so Docker containers can access the mounted directory

This ensures that:
1. The encrypted directory is mounted before Docker starts
2. Docker containers (like Jellyfin) can access the decrypted media

## Troubleshooting

### Mount point not accessible

Verify the mount is active:

```bash
mount | grep library_clear
```

### Permission denied for Docker containers

Ensure the service uses the `-allow_other` flag (included by default) and that `/etc/fuse.conf` contains `user_allow_other`.

### Service fails to start

Check the logs for details:

```bash
sudo journalctl -u gocryptfs-mount -e
```

Common issues:
- Password file not found or incorrect permissions
- Encrypted directory not initialized
- Mount point already in use

## Uninstallation

To remove the service:

```bash
sudo systemctl stop gocryptfs-mount
sudo systemctl disable gocryptfs-mount
sudo rm /etc/systemd/system/gocryptfs-mount.service
sudo systemctl daemon-reload
```
