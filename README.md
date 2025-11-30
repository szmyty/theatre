# theatre

🔐 Encrypted media architecture using gocryptfs 🎬 Jellyfin-based watch parties with SyncPlay ☁️ Automated Google Cloud deployment + Docker stack

## Overview

A self-hosted private movie theatre built on Jellyfin. This project provides encrypted media storage using gocryptfs and is designed for deployment on Google Cloud VMs with automated provisioning.

## Table of Contents

- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [VM Deployment](#vm-deployment)
- [Encrypted Media Workflow](#encrypted-media-workflow)
- [Uploading Media](#uploading-media)
- [Accessing Jellyfin](#accessing-jellyfin)
- [Using SyncPlay for Watch Parties](#using-syncplay-for-watch-parties)
- [Future Automation Notes](#future-automation-notes)
- [License](#license)

## Architecture

The Theatre project is built around a layered architecture designed for security, privacy, and ease of deployment:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Users / Clients                          │
│                   (Web Browser, Mobile Apps)                    │
└─────────────────────────────────┬───────────────────────────────┘
                                  │ HTTP/HTTPS (8096/8920)
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Google Cloud VM (Debian 12)                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     Docker Container                       │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │               Jellyfin Media Server                  │  │  │
│  │  │         (Streaming, Transcoding, SyncPlay)          │  │  │
│  │  └────────────────────────┬────────────────────────────┘  │  │
│  └───────────────────────────┼───────────────────────────────┘  │
│                              │ Read-only mount                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Decrypted Mount (/srv/library_clear)          │  │
│  │                   (gocryptfs FUSE mount)                   │  │
│  └────────────────────────────┬──────────────────────────────┘  │
│                               │ Transparent encryption           │
│                               ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │      Encrypted Storage (/mnt/disks/data/.library_encrypted)│  │
│  │             (AES-256-GCM encrypted files)                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     Systemd Services                       │  │
│  │  • gocryptfs-mount.service (auto-mount on boot)           │  │
│  │  • duckdns-update.timer (dynamic DNS every 5 min)         │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Purpose |
|-----------|---------|
| **Jellyfin** | Open-source media server for streaming video content with native SyncPlay support |
| **gocryptfs** | FUSE-based encryption layer providing transparent encryption/decryption of media files |
| **Docker** | Container runtime for running Jellyfin in an isolated, reproducible environment |
| **Cloud-Init** | Automated VM provisioning on first boot (installs dependencies, clones repo, runs bootstrap) |
| **DuckDNS** | Free dynamic DNS service for accessing the server via a stable hostname |
| **Systemd** | Service management for automatic gocryptfs mounting and DuckDNS updates |

### Security Model

1. **Encryption at Rest**: All media files are encrypted using gocryptfs with AES-256-GCM
2. **Runtime Decryption**: Files are decrypted on-the-fly only when accessed, never stored unencrypted on disk
3. **Password Protection**: The gocryptfs password is required to mount the filesystem
4. **Read-Only Access**: Jellyfin mounts the media directory as read-only to prevent accidental modifications

## Project Structure

```
theatre/
├── config/
│   ├── .env.example          # Environment variables template
│   └── jellyfin/             # Jellyfin configuration (gitignored)
├── docs/
│   ├── SETUP.md              # Detailed encrypted storage setup guide
│   ├── GOCRYPTFS-SERVICE.md  # Systemd service configuration
│   └── DUCKDNS.md            # Dynamic DNS setup guide
├── infrastructure/
│   ├── bootstrap.sh          # VM bootstrap script
│   ├── cloud-init.yaml       # Cloud-init configuration for automated provisioning
│   └── systemd/
│       ├── gocryptfs-mount.service  # Auto-mount encrypted storage on boot
│       ├── duckdns-update.service   # DuckDNS update service
│       └── duckdns-update.timer     # Timer for periodic DNS updates
├── media/
│   ├── encrypted/            # Local gocryptfs encrypted storage
│   └── decrypted/            # Local gocryptfs mount point (gitignored)
├── scripts/
│   ├── upload-media.sh       # Upload media files to remote VM
│   └── update-duckdns.sh     # Manual DuckDNS update script
├── docker-compose.yml        # Docker services configuration
└── README.md
```

## Quick Start

### Prerequisites

- Docker and Docker Compose
- gocryptfs (optional, for encrypted media)
- Media files accessible at `/srv/library_clear` (or configure your own path)

### Plain Docker Deployment (Without Encryption)

1. **Configure environment** (optional):
   ```bash
   cp config/.env.example .env
   # Edit .env with your settings
   ```

2. **Ensure media directory exists**:
   ```bash
   # By default, media is expected at /srv/library_clear
   # You can modify the volume mount in docker-compose.yml if needed
   sudo mkdir -p /srv/library_clear
   ```

3. **Start Jellyfin**:
   ```bash
   docker compose up -d
   ```

4. **Access Jellyfin**:
   - HTTP: http://localhost:8096
   - HTTPS: https://localhost:8920 (requires SSL certificate configuration in Jellyfin)

### Stopping

```bash
docker compose down
# If using encrypted storage:
fusermount -u media/decrypted
```

## VM Deployment

The Theatre project supports automated deployment to Google Cloud VMs using cloud-init and GitHub Actions.

### Prerequisites

1. A Google Cloud Platform account with billing enabled
2. A GCP project with Compute Engine API enabled
3. GitHub repository secrets configured:
   - `GCP_PROJECT_ID`: Your Google Cloud project ID
   - `GCP_ZONE`: The zone for your VM (e.g., `us-central1-a`)
   - `GCP_SA_EMAIL`: Service account email with Compute Engine permissions
4. Workload Identity Federation configured between GitHub and GCP

### Automated Deployment (GitHub Actions)

1. **Configure repository secrets** in GitHub:
   - Go to **Settings** → **Secrets and variables** → **Actions**
   - Add the required secrets listed above

2. **Trigger the deployment**:
   - Go to **Actions** → **Deploy VM**
   - Click **Run workflow**

The workflow will:
- Create a new VM or update an existing one
- Use cloud-init to automatically provision the VM
- Install Docker, gocryptfs, and required dependencies
- Clone the repository and run the bootstrap script

### Manual Deployment

If you prefer to deploy manually or to a different cloud provider:

1. **Create a VM** with Debian 12 (or Ubuntu 22.04+)

2. **SSH into the VM** and clone the repository:
   ```bash
   git clone https://github.com/szmyty/theatre.git /opt/theatre/repo
   ```

3. **Run the bootstrap script**:
   ```bash
   sudo /opt/theatre/repo/infrastructure/bootstrap.sh
   ```

4. **Initialize gocryptfs** (first time only):
   ```bash
   sudo gocryptfs --init /srv/library_encrypted
   ```

5. **Create the password file**:
   ```bash
   echo 'your-secure-password' | sudo tee /etc/gocryptfs/passfile > /dev/null
   sudo chmod 600 /etc/gocryptfs/passfile
   ```

6. **Start the gocryptfs mount service**:
   ```bash
   sudo systemctl start gocryptfs-mount
   ```

### Post-Deployment Configuration

After deployment, complete these steps:

1. **Configure DuckDNS** (optional, for dynamic DNS):
   - Follow the instructions in [docs/DUCKDNS.md](docs/DUCKDNS.md)

2. **Set up firewall rules** to allow traffic on ports 8096 (HTTP) and 8920 (HTTPS)

3. **Complete Jellyfin initial setup** by accessing the web interface

## Encrypted Media Workflow

The Theatre project uses gocryptfs for transparent encryption of all media files. This ensures data is encrypted at rest while remaining accessible to Jellyfin.

### How It Works

1. **Encrypted Storage**: All media files are stored encrypted in `/mnt/disks/data/.library_encrypted` (VM) or `media/encrypted` (local)
2. **Decrypted Mount**: gocryptfs mounts the encrypted directory to `/srv/library_clear` (VM) or `media/decrypted` (local)
3. **Transparent Access**: Files are decrypted on-the-fly when read and encrypted when written
4. **Jellyfin Access**: Jellyfin reads media from the decrypted mount point

### First-Time Setup

1. **Create directories**:
   ```bash
   sudo mkdir -p /mnt/disks/data/.library_encrypted
   sudo mkdir -p /srv/library_clear
   ```

2. **Initialize gocryptfs**:
   ```bash
   gocryptfs --init /mnt/disks/data/.library_encrypted
   ```
   
   You'll be prompted to create a password. **Store this password securely** — it's required to mount the encrypted filesystem.

3. **Mount the encrypted filesystem**:
   ```bash
   gocryptfs /mnt/disks/data/.library_encrypted /srv/library_clear
   ```

### Automatic Mounting with Systemd

For production deployments, use the systemd service for automatic mounting:

1. **Configure FUSE** to allow Docker access:
   ```bash
   echo "user_allow_other" | sudo tee -a /etc/fuse.conf
   ```

2. **Create the password file**:
   ```bash
   sudo mkdir -p /etc/gocryptfs
   echo 'your-password' | sudo tee /etc/gocryptfs/password > /dev/null
   sudo chmod 600 /etc/gocryptfs/password
   ```

3. **Create the environment file** at `/etc/gocryptfs/gocryptfs.env`:
   ```bash
   GOCRYPTFS_ENCRYPTED_DIR=/mnt/disks/data/.library_encrypted
   GOCRYPTFS_MOUNT_POINT=/srv/library_clear
   GOCRYPTFS_PASSFILE=/etc/gocryptfs/password
   ```

4. **Install and enable the service**:
   ```bash
   sudo cp infrastructure/systemd/gocryptfs-mount.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now gocryptfs-mount
   ```

### Unmounting

To unmount the encrypted filesystem:
```bash
fusermount -u /srv/library_clear
```

Or using systemd:
```bash
sudo systemctl stop gocryptfs-mount
```

### Important Security Notes

- **Backup your password**: Without the password, encrypted data cannot be recovered
- **Backup gocryptfs.conf**: This file in the encrypted directory contains the encrypted master key
- **Password file security**: Ensure `/etc/gocryptfs/password` has mode 600 and is owned by root

For detailed setup instructions, see [docs/SETUP.md](docs/SETUP.md) and [docs/GOCRYPTFS-SERVICE.md](docs/GOCRYPTFS-SERVICE.md).

## Uploading Media

The project includes a script for uploading media files to the remote VM.

### Using the Upload Script

```bash
./scripts/upload-media.sh <local_file> <remote_host>
```

**Arguments**:
- `local_file`: Path to the local video file to upload
- `remote_host`: Remote host (e.g., `user@hostname` or `user@IP`)

**Examples**:
```bash
# Upload a movie file
./scripts/upload-media.sh /path/to/movie.mp4 user@192.168.1.100

# Upload to a VM with a hostname
./scripts/upload-media.sh movie.mkv ubuntu@theatre.duckdns.org
```

The script will:
1. Validate the file exists and is readable
2. Use SCP with compression to upload the file
3. Copy the file to `/srv/library_clear` on the remote host

### Manual Upload

You can also upload files manually using SCP:

```bash
scp -C /path/to/video.mp4 user@remote-host:/srv/library_clear/
```

### After Uploading

After uploading new media:

1. **Refresh Jellyfin library**:
   - Go to **Dashboard** → **Libraries**
   - Click **Scan All Libraries**

2. **Or wait for automatic scan**: Jellyfin periodically scans for new media (configurable in settings)

## Accessing Jellyfin

### Local Access

- **HTTP**: http://localhost:8096
- **HTTPS**: https://localhost:8920 (requires SSL configuration)

### Remote Access

#### Using DuckDNS (Recommended)

1. Set up DuckDNS following [docs/DUCKDNS.md](docs/DUCKDNS.md)
2. Access via: http://yoursubdomain.duckdns.org:8096

#### Using IP Address

Access via the VM's public IP: http://YOUR_VM_IP:8096

### First-Time Setup

1. **Access the web interface** at http://your-server:8096
2. **Create an admin account** with a strong password
3. **Add media libraries**:
   - Click **Add Media Library**
   - Select content type (Movies, Shows, etc.)
   - Add folder: `/media`
   - Configure metadata providers as desired
4. **Complete the setup wizard**

### Mobile Apps

Jellyfin has official apps for:
- iOS (App Store)
- Android (Google Play, F-Droid)
- Android TV
- Amazon Fire TV
- Roku

Configure the app with your server address (e.g., `http://yoursubdomain.duckdns.org:8096`).

## Using SyncPlay for Watch Parties

SyncPlay is Jellyfin's built-in feature for synchronized playback across multiple users, perfect for hosting virtual watch parties.

### How SyncPlay Works

- One user creates a **SyncPlay group**
- Other users join the group
- Playback is synchronized across all group members
- Play, pause, and seek actions are shared in real-time

### Creating a Watch Party

1. **Start playing** the movie or show you want to watch
2. **Open the playback menu** (click the screen or press the menu button)
3. **Click the SyncPlay icon** (two overlapping circles)
4. **Select "Create Group"**
5. **Share the group name** with your friends

### Joining a Watch Party

1. **Navigate to the same media** the host is playing
2. **Start playback**
3. **Open the playback menu**
4. **Click the SyncPlay icon**
5. **Select "Join Group"** and choose the group name

### SyncPlay Tips

- **Same media required**: All participants must have access to the same media file
- **Buffer time**: SyncPlay accounts for network latency and buffering differences
- **Host controls**: Any group member can control playback (play, pause, seek)
- **Chat**: Use an external chat app for communication during the watch party
- **Permissions**: Ensure all participants have permission to access the media library

### Recommended Settings

For the best SyncPlay experience:

1. **Enable transcoding** if participants have different bandwidth capabilities:
   - **Dashboard** → **Playback** → Enable transcoding

2. **Set appropriate quality**:
   - Each user can set their preferred quality in playback settings

3. **Stable connection**: Recommend all participants use a stable internet connection

## Future Automation Notes

The following automation improvements are planned or in progress:

### Planned Features

- [ ] **Automated SSL/TLS with Let's Encrypt**: Automatic certificate provisioning using Caddy or Certbot
- [ ] **Terraform Infrastructure**: Infrastructure as Code for full GCP deployment automation
- [ ] **Automated Backups**: Scheduled backups of Jellyfin configuration and encrypted media metadata
- [ ] **Monitoring & Alerting**: Integration with Prometheus/Grafana for system monitoring
- [ ] **Multi-region Deployment**: Support for deploying to multiple regions for better latency
- [ ] **GitHub Actions Improvements**:
  - Automatic VM shutdown/startup scheduling
  - Deployment status notifications
  - Automated gocryptfs password management with Secret Manager

### Current Automation

| Feature | Status | Description |
|---------|--------|-------------|
| VM Provisioning | ✅ Complete | Cloud-init automated setup |
| Docker Deployment | ✅ Complete | Docker Compose configuration |
| gocryptfs Auto-mount | ✅ Complete | Systemd service for boot-time mounting |
| DuckDNS Updates | ✅ Complete | Systemd timer for periodic DNS updates |
| GitHub Actions Deploy | ✅ Complete | One-click VM deployment workflow |

### Contributing

Contributions to automation improvements are welcome! Check the [GitHub Issues](../../issues) for current tasks or open a new issue to propose enhancements.

## License

MIT License - see [LICENSE](LICENSE) for details.
