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
                                  │ HTTPS (443)
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Google Cloud VM (Debian 12)                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Docker Containers                        │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │                  Caddy Reverse Proxy                 │  │  │
│  │  │        (Automatic HTTPS via DuckDNS DNS-01)         │  │  │
│  │  └────────────────────────┬────────────────────────────┘  │  │
│  │                           │ HTTP (8096)                    │  │
│  │                           ▼                                │  │
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
│  │      Encrypted Storage (/mnt/disks/media/.library_encrypted)│  │
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
| **Caddy** | Reverse proxy with automatic HTTPS via Let's Encrypt and DuckDNS DNS-01 challenge |
| **gocryptfs** | FUSE-based encryption layer providing transparent encryption/decryption of media files |
| **Docker** | Container runtime for running Jellyfin and Caddy in isolated, reproducible environments |
| **Cloud-Init** | Automated VM provisioning on first boot (installs dependencies, clones repo, runs bootstrap) |
| **DuckDNS** | Free dynamic DNS service for accessing the server via a stable hostname |
| **Systemd** | Service management for automatic gocryptfs mounting and DuckDNS updates |

### Security Model

1. **Encryption in Transit**: All traffic is encrypted via HTTPS using automatic TLS certificates from Let's Encrypt
2. **Encryption at Rest**: All media files are encrypted using gocryptfs with AES-256-GCM
3. **Runtime Decryption**: Files are decrypted on-the-fly only when accessed, never stored unencrypted on disk
4. **Password Protection**: The gocryptfs password is required to mount the filesystem
5. **Read-Only Access**: Jellyfin mounts the media directory as read-only to prevent accidental modifications

## Project Structure

```
theatre/
├── config/
│   ├── .env.example          # Environment variables template
│   └── caddy/                # Caddy reverse proxy configuration
│       ├── Caddyfile         # Caddy configuration file
│       └── Dockerfile        # Custom Caddy build with DuckDNS module
├── docs/
│   ├── SETUP.md              # Detailed encrypted storage setup guide
│   ├── GOCRYPTFS-SERVICE.md  # Systemd service configuration
│   ├── DUCKDNS.md            # Dynamic DNS setup guide
│   ├── DEPLOY-SCRIPTS.md     # Deployment scripts documentation
│   └── ENVIRONMENT-VARIABLES.md  # Environment variable naming conventions
├── infrastructure/
│   ├── bootstrap.sh          # VM bootstrap script
│   ├── cloud-init.yaml       # Cloud-init configuration for automated provisioning
│   ├── scripts/              # Modular provisioning scripts
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

**Note:** On deployed VMs, Jellyfin configuration is stored at `/mnt/disks/media/jellyfin_config` on the attached media disk to avoid disk space issues on the root volume.

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
   - Local HTTP: http://localhost:8096
   - HTTPS (requires DuckDNS setup): https://yourdomain.duckdns.org

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
   - `GCP_PROJECT_NUMBER`: Your Google Cloud project number
   - `GCP_ZONE`: The zone for your VM (e.g., `us-central1-a`)
   - `GCP_SA_EMAIL`: Service account email with Compute Engine permissions
   - `GOCRYPTFS_PASSWORD`: Password for encrypting media files
   - `DUCKDNS_TOKEN`: Your DuckDNS authentication token
4. GitHub repository variables configured:
   - `GCP_VM_NAME`: VM name (defaults to `theatre-vm`)
   - `GCP_MEDIA_DISK_NAME`: Media disk name (defaults to `theatre-media-disk`)
   - `DOMAIN_NAME`: Your DuckDNS domain (e.g., `movietheatre.duckdns.org`)
   - `DUCKDNS_DOMAIN`: Your DuckDNS subdomain (e.g., `movietheatre`)
5. Workload Identity Federation configured between GitHub and GCP

### Full Stack Deployment (Recommended)

The **Deploy Full Stack** workflow provides a complete, idempotent deployment of the entire theatre platform:

1. **Configure repository secrets and variables** in GitHub:
   - Go to **Settings** → **Secrets and variables** → **Actions**
   - Add all required secrets and variables listed above

2. **Trigger the deployment**:
   - Go to **Actions** → **Deploy Full Stack**
   - Click **Run workflow**

The workflow will:
- Create or reuse the VM (idempotent)
- Create or reuse the media disk (idempotent)
- Attach the media disk to the VM
- Install fuse3, gocryptfs, Docker, and docker-compose
- Format the media disk (only if unformatted)
- Mount the disk at `/mnt/disks/media`
- Initialize gocryptfs encryption (only if not initialized)
- Mount the decrypted view at `/srv/library_clear`
- Install and enable systemd services for gocryptfs and DuckDNS
- **Write `.env` file with `DOMAIN_NAME`, `DUCKDNS_TOKEN`, and `JELLYFIN_URL` for Caddy and Jellyfin**
- Start Jellyfin and Caddy containers
- Obtain HTTPS certificates via Let's Encrypt
- Verify all components and print a deployment summary

**Note:** The `.env` file at `/opt/theatre/repo/.env` is automatically generated during deployment from GitHub secrets and variables. This file provides Caddy with the DuckDNS token required for automatic HTTPS certificate provisioning.

After successful deployment, access your theatre at:
```
https://${DOMAIN_NAME}
```

**Note:** The system will be fully deployed but with no movies. See [Uploading Media](#uploading-media) for the next step.

### Basic VM Deployment

For basic VM creation without full provisioning:

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
   sudo gocryptfs --init /mnt/disks/media/.library_encrypted
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

1. **Configure DuckDNS and HTTPS**:
   - Follow the instructions in [docs/DUCKDNS.md](docs/DUCKDNS.md)
   - Set `DOMAIN_NAME` and `DUCKDNS_TOKEN` in your `.env` file
   - Caddy will automatically obtain TLS certificates

2. **Set up firewall rules** to allow traffic on ports:
   - Port 80 (HTTP - for ACME challenges)
   - Port 443 (HTTPS)
   - Port 8096 (optional, for direct HTTP access to Jellyfin)

3. **Complete Jellyfin initial setup** by accessing the web interface

## Encrypted Media Workflow

The Theatre project uses gocryptfs for transparent encryption of all media files. This ensures data is encrypted at rest while remaining accessible to Jellyfin.

### How It Works

1. **Encrypted Storage**: All media files are stored encrypted in `/mnt/disks/media/.library_encrypted` (VM) or `media/encrypted` (local)
2. **Decrypted Mount**: gocryptfs mounts the encrypted directory to `/srv/library_clear` (VM) or `media/decrypted` (local)
3. **Transparent Access**: Files are decrypted on-the-fly when read and encrypted when written
4. **Jellyfin Access**: Jellyfin reads media from the decrypted mount point

### First-Time Setup

1. **Create directories**:
   ```bash
   sudo mkdir -p /mnt/disks/media/.library_encrypted
   sudo mkdir -p /srv/library_clear
   ```

2. **Initialize gocryptfs**:
   ```bash
   gocryptfs --init /mnt/disks/media/.library_encrypted
   ```
   
   You'll be prompted to create a password. **Store this password securely** — it's required to mount the encrypted filesystem.

3. **Mount the encrypted filesystem**:
   ```bash
   gocryptfs /mnt/disks/media/.library_encrypted /srv/library_clear
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
   echo 'your-password' | sudo tee /etc/gocryptfs/passfile > /dev/null
   sudo chmod 600 /etc/gocryptfs/passfile
   ```

3. **Create the environment file** at `/etc/gocryptfs/gocryptfs.env`:
   ```bash
   GOCRYPTFS_ENCRYPTED_DIR=/mnt/disks/media/.library_encrypted
   GOCRYPTFS_MOUNT_POINT=/srv/library_clear
   GOCRYPTFS_PASSFILE=/etc/gocryptfs/passfile
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
- **Password file security**: Ensure `/etc/gocryptfs/passfile` has mode 600 and is owned by root

For detailed setup instructions, see [docs/SETUP.md](docs/SETUP.md) and [docs/GOCRYPTFS-SERVICE.md](docs/GOCRYPTFS-SERVICE.md).

## Uploading Media

After running the **Deploy Full Stack** workflow, the system is fully deployed but has no movies yet. This is intentional — uploading media is the next manual step.

The project includes a script for uploading media files to the remote VM. When you upload files to `/srv/library_clear`, gocryptfs automatically encrypts them on write, and Jellyfin immediately sees them.

### Using the Upload Script

```bash
./scripts/upload-media.sh <local_file> <remote_host>
```

**Arguments**:
- `local_file`: Path to the local video file to upload
- `remote_host`: Remote host (e.g., `user@hostname` or `user@IP`)

**Examples**:
```bash
# Upload a movie file using your DuckDNS domain
./scripts/upload-media.sh /path/to/movie.mp4 user@movietheatre.duckdns.org

# Upload a movie file using the VM's IP address
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

### Remote Access with HTTPS (Recommended)

The Theatre project includes Caddy reverse proxy with automatic HTTPS via Let's Encrypt and DuckDNS.

#### Prerequisites

1. A DuckDNS account and subdomain (e.g., `movietheatre.duckdns.org`)
2. Your DuckDNS authentication token

#### Configuration

1. **Set up environment variables** in your `.env` file:
   ```bash
   cp config/.env.example .env
   # Edit .env with your values:
   DOMAIN_NAME=movietheatre.duckdns.org
   DUCKDNS_TOKEN=your-duckdns-token-here
   ```

2. **Set up DuckDNS dynamic DNS** following [docs/DUCKDNS.md](docs/DUCKDNS.md)

3. **Configure firewall rules** to allow traffic on ports:
   - Port 80 (HTTP - for automatic HTTP to HTTPS redirects)
   - Port 443 (HTTPS)

4. **Start the services**:
   ```bash
   docker compose up -d
   ```

5. **Access Jellyfin** via HTTPS:
   - **HTTPS**: https://movietheatre.duckdns.org (or your configured domain)

Caddy will automatically:
- Obtain TLS certificates from Let's Encrypt using DNS-01 challenge
- Redirect HTTP to HTTPS
- Renew certificates before they expire
- Store certificates in the `caddy_data` volume

#### Using DuckDNS without HTTPS

If you prefer HTTP-only access:
1. Set up DuckDNS following [docs/DUCKDNS.md](docs/DUCKDNS.md)
2. Access via: http://yoursubdomain.duckdns.org:8096

#### Using IP Address

Access via the VM's public IP: http://YOUR_VM_IP:8096

### First-Time Setup

1. **Access the web interface** at https://your-domain.duckdns.org (or http://localhost:8096 for local access)
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

Configure the app with your server address (e.g., `https://yoursubdomain.duckdns.org`).

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

## Backup and Disaster Recovery

The Theatre project includes a comprehensive backup strategy for disaster recovery. See [docs/BACKUP.md](docs/BACKUP.md) for full documentation.

### Backup Components

| Component | Method | Frequency |
|-----------|--------|-----------|
| Media Disk | GCP Disk Snapshots | Daily at 4:00 AM UTC |
| Jellyfin Config | GCS Sync | Daily at 3:00 AM UTC |
| gocryptfs.conf | GCS Sync | Daily at 3:00 AM UTC |

### Quick Start

1. **Create GCS bucket** for configuration backups
2. **Add `BACKUP_BUCKET` variable** to GitHub repository
3. **Create snapshot schedule** using `infrastructure/scripts/ensure_snapshot_schedule.sh`
4. **Enable VM-side backups** by running `infrastructure/scripts/ensure_backup.sh` on the VM

### Manual Backup

Via GitHub Actions:
1. Go to **Actions** → **Backup**
2. Click **Run workflow**

Via SSH:
```bash
sudo /opt/theatre/repo/scripts/backup-to-gcs.sh --bucket gs://your-backup-bucket
```

## Future Automation Notes

The following automation improvements are planned or in progress:

### Planned Features

- [ ] **Terraform Infrastructure**: Infrastructure as Code for full GCP deployment automation
- [ ] **Monitoring & Alerting**: Integration with Prometheus/Grafana for system monitoring
- [ ] **Multi-region Deployment**: Support for deploying to multiple regions for better latency
- [ ] **GitHub Actions Improvements**:
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
| Automatic HTTPS | ✅ Complete | Caddy reverse proxy with Let's Encrypt via DuckDNS DNS-01 |
| Automated Backups | ✅ Complete | GCS sync and GCP disk snapshots with GitHub Actions workflow |
| VM Schedule | ✅ Complete | Automated VM shutdown/startup to reduce GCP costs |

### VM Schedule

The **VM Schedule** workflow automatically manages the VM power state to reduce GCP costs during inactive periods.

#### Default Schedule (UTC)

| Time | Action | Purpose |
|------|--------|---------|
| 07:00 | Start VM | Begin active hours |
| 23:00 | Stop VM | End active hours, reduce costs |

#### Manual Control

You can also manually start, stop, or check the VM status:

1. Go to **Actions** → **VM Schedule**
2. Click **Run workflow**
3. Select the action:
   - `start` - Start the VM
   - `stop` - Stop the VM
   - `status` - Check current VM status

#### Cost Savings

With the default schedule, the VM runs for 16 hours per day instead of 24 hours, reducing compute costs by approximately 33%. Stopped VMs only incur storage costs for attached disks.

**Note:** When the VM is stopped:
- The theatre will be inaccessible
- No charges for compute resources
- Persistent disk storage charges still apply
- DuckDNS will point to the last known IP (may become stale)

### Contributing

Contributions to automation improvements are welcome! Check the [GitHub Issues](../../issues) for current tasks or open a new issue to propose enhancements.

## License

MIT License - see [LICENSE](LICENSE) for details.
