# Backup and Disaster Recovery

This document describes the backup strategy and disaster recovery procedures for the Theatre project.

## Overview

The Theatre project implements a comprehensive backup strategy with three layers of protection:

1. **Automated GCP Disk Snapshots**: Daily snapshots of the media disk for full disaster recovery
2. **GCS Configuration Backups**: Syncs of Jellyfin config and gocryptfs.conf to Cloud Storage
3. **Manual Snapshots**: On-demand snapshots via GitHub Actions

## Backup Components

### What Gets Backed Up

| Component | Location | Backup Method | Frequency |
|-----------|----------|---------------|-----------|
| Media Disk (full) | `/mnt/disks/media` | GCP Snapshots | Daily at 4:00 AM UTC |
| Jellyfin Config | `/mnt/disks/media/jellyfin_config` | GCS Sync | Daily at 3:00 AM UTC |
| gocryptfs.conf | `/mnt/disks/media/.library_encrypted/gocryptfs.conf` | GCS Sync | Daily at 3:00 AM UTC |

### Critical Files

The following files are essential for disaster recovery:

1. **gocryptfs.conf** - Contains the encrypted master key. Without this file and the password, encrypted media cannot be recovered.
2. **gocryptfs password** - The password used to decrypt gocryptfs.conf. Store this securely outside of the system (e.g., password manager).
3. **Jellyfin configuration** - Contains user accounts, library settings, watch history, and metadata.

## Setting Up Backups

### 1. Create GCS Bucket

First, create a Cloud Storage bucket for configuration backups:

```bash
# Create bucket with versioning enabled
gsutil mb -l us gs://your-backup-bucket
gsutil versioning set on gs://your-backup-bucket

# Set lifecycle policy to delete old versions after 30 days
cat > /tmp/lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"numNewerVersions": 5}
    }
  ]
}
EOF
gsutil lifecycle set /tmp/lifecycle.json gs://your-backup-bucket
```

### 2. Configure GitHub Repository

Add the following to your repository:

**Secrets:**
- `GCP_SA_KEY` - Service account key with permissions:
  - `Storage Object Admin` for the backup bucket
  - `Compute Snapshot Creator` for disk snapshots

**Variables:**
- `BACKUP_BUCKET` - GCS bucket name (e.g., `gs://your-backup-bucket`)

### 3. Create Disk Snapshot Schedule

Run the following to create an automated snapshot schedule:

```bash
# From your local machine with gcloud configured
export GCP_PROJECT_ID=your-project-id
export GCP_ZONE=us-central1-a

./infrastructure/scripts/ensure_snapshot_schedule.sh
```

Or via GitHub Actions: The Deploy Full Stack workflow can be extended to include snapshot schedule creation.

### 4. Enable VM-Side Backups

SSH to the VM and configure the backup timer:

```bash
# Set backup bucket
export BACKUP_BUCKET=gs://your-backup-bucket

# Run setup script
sudo -E /opt/theatre/scripts/ensure_backup.sh
```

## Manual Operations

### Trigger Manual Backup

**Via GitHub Actions:**
1. Go to **Actions** → **Backup**
2. Click **Run workflow**
3. Select backup type (config, snapshot, or both)

**Via SSH:**
```bash
# Run backup script directly
sudo /opt/theatre/repo/scripts/backup-to-gcs.sh --bucket gs://your-backup-bucket
```

### Create Manual Snapshot

```bash
# Create a snapshot
gcloud compute snapshots create theatre-media-disk-manual-$(date +%Y%m%d) \
  --source-disk=theatre-media-disk \
  --source-disk-zone=us-central1-a \
  --description="Manual backup before maintenance"
```

### List Snapshots

```bash
gcloud compute snapshots list --filter="sourceDisk~theatre-media-disk"
```

## Disaster Recovery

### Scenario 1: VM Failure (Disk Intact)

If the VM fails but the media disk is intact:

1. **Create new VM** using Deploy Full Stack workflow
2. **Attach existing disk** - the workflow handles this automatically
3. **Verify services** are running

### Scenario 2: Disk Failure (Restore from Snapshot)

If the media disk is corrupted or lost:

1. **Create disk from snapshot:**
   ```bash
   gcloud compute disks create theatre-media-disk-restored \
     --source-snapshot=theatre-media-disk-YYYYMMDD \
     --zone=us-central1-a
   ```

2. **Detach old disk (if attached):**
   ```bash
   gcloud compute instances detach-disk theatre-vm --disk=theatre-media-disk
   ```

3. **Attach restored disk:**
   ```bash
   gcloud compute instances attach-disk theatre-vm \
     --disk=theatre-media-disk-restored \
     --device-name=media-disk
   ```

4. **Rename or update references** if needed

### Scenario 3: Full Disaster Recovery

For complete disaster recovery (new project, new region, etc.):

1. **Deploy new infrastructure:**
   ```bash
   # Run Deploy Full Stack workflow in new environment
   ```

2. **Create disk from snapshot** (if snapshot exists in new region, may need to copy first)

3. **Restore configuration from GCS:**
   ```bash
   # SSH to new VM
   sudo /opt/theatre/repo/scripts/restore-from-gcs.sh --bucket gs://your-backup-bucket
   ```

4. **Set gocryptfs password:**
   ```bash
   echo 'your-password' | sudo tee /etc/gocryptfs/passfile > /dev/null
   sudo chmod 600 /etc/gocryptfs/passfile
   ```

5. **Start services:**
   ```bash
   sudo systemctl start gocryptfs-mount
   docker compose -f /opt/theatre/repo/docker-compose.yml up -d
   ```

### Scenario 4: Restore gocryptfs.conf Only

If only gocryptfs.conf is corrupted:

1. **Stop gocryptfs mount:**
   ```bash
   sudo systemctl stop gocryptfs-mount
   ```

2. **Restore gocryptfs.conf:**
   ```bash
   sudo /opt/theatre/repo/scripts/restore-from-gcs.sh \
     --bucket gs://your-backup-bucket \
     --gocryptfs-only
   ```

3. **Restart gocryptfs mount:**
   ```bash
   sudo systemctl start gocryptfs-mount
   ```

### Scenario 5: Restore Jellyfin Config Only

If only Jellyfin configuration needs to be restored:

1. **Stop Jellyfin:**
   ```bash
   docker compose -f /opt/theatre/repo/docker-compose.yml down
   ```

2. **Restore Jellyfin config:**
   ```bash
   sudo /opt/theatre/repo/scripts/restore-from-gcs.sh \
     --bucket gs://your-backup-bucket \
     --jellyfin-only
   ```

3. **Start Jellyfin:**
   ```bash
   docker compose -f /opt/theatre/repo/docker-compose.yml up -d
   ```

## Backup Verification

### Check Backup Status

**View latest backup manifest:**
```bash
gsutil cat gs://your-backup-bucket/theatre-backup/manifests/latest-manifest.json
```

**List backup contents:**
```bash
gsutil ls -l gs://your-backup-bucket/theatre-backup/
```

**Check systemd timer status (on VM):**
```bash
systemctl status theatre-backup.timer
journalctl -u theatre-backup.service --since "24 hours ago"
```

### Check Snapshot Status

```bash
gcloud compute snapshots list \
  --filter="sourceDisk~theatre-media-disk" \
  --sort-by=~creationTimestamp \
  --limit=10
```

## Monitoring and Alerts

### Recommended Monitoring

1. **Cloud Monitoring** - Set up alerts for:
   - Failed snapshot creation
   - Storage bucket errors
   - VM downtime

2. **GitHub Actions** - Check workflow run history for backup failures

3. **Systemd Logs** - Review backup timer logs:
   ```bash
   journalctl -u theatre-backup.service
   ```

## Security Considerations

1. **gocryptfs password** - Never store in version control or cloud storage. Use a password manager.
2. **Service account** - Use least-privilege access for backup operations.
3. **Bucket access** - Restrict bucket access to the VM service account and admins only.
4. **Backup encryption** - GCS provides encryption at rest by default. Consider customer-managed encryption keys (CMEK) for additional security.

## Troubleshooting

### Backup Script Fails

```bash
# Check if gsutil is authenticated
gsutil ls gs://your-backup-bucket

# Check if paths exist
ls -la /mnt/disks/media/jellyfin_config
ls -la /mnt/disks/media/.library_encrypted/gocryptfs.conf
```

### Snapshot Creation Fails

```bash
# Check disk status
gcloud compute disks describe theatre-media-disk --zone=us-central1-a

# Check quota
gcloud compute regions describe us-central1 --format="table(quotas)"
```

### Timer Not Running

```bash
# Check timer status
systemctl status theatre-backup.timer

# Check if enabled
systemctl is-enabled theatre-backup.timer

# Re-enable if needed
sudo systemctl enable --now theatre-backup.timer
```
