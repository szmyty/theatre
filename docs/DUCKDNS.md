# DuckDNS Integration

This document explains how to set up DuckDNS dynamic DNS for the Theatre project.

## Overview

DuckDNS is a free dynamic DNS service that allows you to access your server using a domain name (e.g., `yourname.duckdns.org`) even when your public IP address changes. The Theatre project includes a systemd timer that automatically updates your DuckDNS record every 5 minutes.

## Prerequisites

- A DuckDNS account ([https://www.duckdns.org](https://www.duckdns.org))
- A DuckDNS subdomain registered to your account
- Your DuckDNS authentication token

## Required Secrets

For GitHub Actions deployment, add these secrets to your repository:

| Secret | Description |
|--------|-------------|
| `DUCKDNS_TOKEN` | Your DuckDNS authentication token (found on the DuckDNS website after logging in) |
| `DUCKDNS_DOMAIN` | Your DuckDNS subdomain (e.g., `myserver` for `myserver.duckdns.org`) |

To add secrets:
1. Go to your repository on GitHub
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret with its corresponding value

## Docker Secrets Setup (for Caddy)

The DuckDNS token for Caddy is managed via Docker secrets for better security.

### Setup Instructions

1. Copy the example secret file:
   ```bash
   cp config/secrets/duckdns_token.txt.example config/secrets/duckdns_token.txt
   ```

2. Edit the file with your actual DuckDNS token:
   ```bash
   nano config/secrets/duckdns_token.txt
   ```

3. Ensure the file has restricted permissions:
   ```bash
   chmod 600 config/secrets/duckdns_token.txt
   ```

The secret is automatically mounted into the Caddy container at `/run/secrets/duckdns_token` and read by the Caddyfile.

## VM Installation

### 1. Create the Environment File

Create the DuckDNS configuration directory and environment file:

```bash
sudo mkdir -p /etc/duckdns
sudo touch /etc/duckdns/duckdns.env
sudo chmod 600 /etc/duckdns/duckdns.env
```

Add the following content to `/etc/duckdns/duckdns.env`:

```bash
# DuckDNS configuration
DUCKDNS_TOKEN=your-duckdns-token-here
DUCKDNS_DOMAIN=your-subdomain
```

Replace `your-duckdns-token-here` with your actual DuckDNS token and `your-subdomain` with your DuckDNS subdomain.

### 2. Install the Systemd Service and Timer

Copy the systemd files to the system directory:

```bash
sudo cp /opt/theatre/repo/infrastructure/systemd/duckdns-update.service /etc/systemd/system/
sudo cp /opt/theatre/repo/infrastructure/systemd/duckdns-update.timer /etc/systemd/system/
```

### 3. Enable and Start the Timer

Enable the timer to start on boot and start it immediately:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now duckdns-update.timer
```

## Usage

### Check Timer Status

```bash
sudo systemctl status duckdns-update.timer
```

### Check Service Status (Last Update)

```bash
sudo systemctl status duckdns-update.service
```

### Manually Trigger an Update

```bash
sudo systemctl start duckdns-update.service
```

### View Logs

```bash
sudo journalctl -u duckdns-update.service
```

### List Timer Schedule

```bash
sudo systemctl list-timers duckdns-update.timer
```

## How It Works

1. The `duckdns-update.timer` runs the `duckdns-update.service` every 5 minutes
2. The service executes the `update-duckdns.sh` script
3. The script sends a request to DuckDNS API with your token
4. DuckDNS automatically detects your public IP and updates the DNS record

## Troubleshooting

### Update Fails

Check the service logs:

```bash
sudo journalctl -u duckdns-update.service -e
```

Common issues:
- **Invalid token**: Verify your token in `/etc/duckdns/duckdns.env`
- **Network issues**: Ensure the VM has internet access
- **Permission denied**: Verify the environment file permissions (`chmod 600`)

### Timer Not Running

Check if the timer is enabled and active:

```bash
sudo systemctl is-enabled duckdns-update.timer
sudo systemctl is-active duckdns-update.timer
```

If not enabled, run:

```bash
sudo systemctl enable --now duckdns-update.timer
```

### Manual Test

Test the script manually:

```bash
source /etc/duckdns/duckdns.env
/opt/theatre/repo/scripts/update-duckdns.sh
```

## Uninstallation

To remove the DuckDNS integration:

```bash
sudo systemctl stop duckdns-update.timer
sudo systemctl disable duckdns-update.timer
sudo rm /etc/systemd/system/duckdns-update.service
sudo rm /etc/systemd/system/duckdns-update.timer
sudo systemctl daemon-reload
sudo rm -rf /etc/duckdns
```
