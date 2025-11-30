# theatre

🔐 Encrypted media architecture using gocryptfs 🎬 Jellyfin-based watch parties with SyncPlay ☁️ Automated Google Cloud deployment + Docker stack

## Overview

A self-hosted private movie theatre built on Jellyfin. This project provides encrypted media storage using gocryptfs and is designed for future deployment on Google Cloud VMs.

## Goals

- **Encrypted Media Storage**: All media files are stored encrypted using gocryptfs
- **gocryptfs Mount**: Decrypt media at runtime without storing unencrypted files on disk
- **Jellyfin Media Server**: Stream media with a modern, self-hosted solution
- **SyncPlay Support**: Watch together with friends in sync
- **Google Cloud VM Deployment**: Future cloud deployment automation

## Project Structure

```
theatre/
├── config/
│   └── jellyfin/        # Jellyfin configuration (gitignored)
├── media/
│   ├── encrypted/       # gocryptfs encrypted storage
│   └── decrypted/       # gocryptfs mount point (gitignored)
├── docker-compose.yml   # Docker services configuration
└── README.md
```

## Quick Start

### Prerequisites

- Docker and Docker Compose
- gocryptfs (for encrypted media)

### Setup

1. **Initialize encrypted storage** (first time only):
   ```bash
   gocryptfs -init media/encrypted
   ```

2. **Mount encrypted storage**:
   ```bash
   gocryptfs media/encrypted media/decrypted
   ```

3. **Start Jellyfin**:
   ```bash
   docker compose up -d
   ```

4. **Access Jellyfin**: Open http://localhost:8096

### Stopping

```bash
docker compose down
fusermount -u media/decrypted
```

## Future Plans

Tracked via [GitHub Issues](../../issues):

- [ ] Google Cloud VM deployment scripts
- [ ] Automated backup of encrypted media
- [ ] SSL/TLS configuration with Let's Encrypt
- [ ] User authentication improvements
- [ ] SyncPlay configuration guide

## License

MIT License - see [LICENSE](LICENSE) for details.
