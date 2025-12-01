# Repository Audit & Improvement Report

**Generated:** 2025-11-30  
**Repository:** szmyty/theatre  
**Purpose:** Comprehensive audit to identify improvements, security risks, best practices, and production-readiness enhancements.

---

## Executive Summary

The Theatre project is a well-structured, self-hosted media streaming platform using Jellyfin, gocryptfs encryption, and Caddy reverse proxy, with automated deployment to Google Cloud VMs. The architecture demonstrates good security practices (encryption at rest and in transit) and follows Infrastructure as Code principles.

This audit identified **28 findings** across security, reliability, maintainability, and best practices. Key highlights include:

- **Security:** Some password handling could be improved, Docker image pinning recommended
- **Reliability:** Missing health checks, restart policies could be more robust
- **Maintainability:** Some code duplication between workflows and scripts
- **Best Practices:** Documentation is comprehensive but could benefit from contribution guidelines

**Priority Distribution:**
- 🔴 High: 6 findings
- 🟡 Medium: 13 findings
- 🟢 Low: 9 findings

---

## Detailed Findings

### 1. Security

#### 1.1 Docker Image Tags Not Pinned to Specific Versions
**Priority:** 🔴 High  
**Location:** `docker-compose.yml`, `config/caddy/Dockerfile`

**Finding:** The project uses `:latest` tags for Docker images which can lead to unexpected breaking changes during deployments.

```yaml
# docker-compose.yml line 3
image: jellyfin/jellyfin:latest

# config/caddy/Dockerfile lines 2, 7
FROM caddy:builder AS builder
FROM caddy:latest
```

**Recommendation:** Pin images to specific versions (e.g., `jellyfin/jellyfin:10.8.13`, `caddy:2.7.6-builder`, `caddy:2.7.6`) and use Dependabot or Renovate for automated updates.

**Suggested Issue Title:** `Pin Docker images to specific versions for reproducible builds`

---

#### 1.2 Password File Handling in Provisioning Script
**Priority:** 🔴 High  
**Location:** `.github/workflows/deploy_full_stack.yml` (lines 318-323)

**Finding:** While secrets are handled via environment file (good), the password is written directly to disk. Consider using echo with restricted file creation mode atomically.

```bash
touch "${PASSFILE}"
chmod 600 "${PASSFILE}"
printf '%s' "${GOCRYPTFS_PASSWORD}" > "${PASSFILE}"
```

**Recommendation:** Use `install` command or write with umask set to prevent brief window of world-readable file:

```bash
(umask 077 && printf '%s' "${GOCRYPTFS_PASSWORD}" > "${PASSFILE}")
```

**Suggested Issue Title:** `Improve atomic password file creation in provisioning script`

---

#### 1.3 Missing HSTS and Security Headers in Caddy
**Priority:** 🟡 Medium  
**Location:** `config/caddy/Caddyfile`

**Finding:** The Caddyfile lacks explicit security headers like HSTS, CSP, X-Content-Type-Options.

**Recommendation:** Add security headers:

```caddyfile
{$DOMAIN_NAME} {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
    reverse_proxy jellyfin:8096
    tls {
        dns duckdns {$DUCKDNS_TOKEN}
    }
}
```

**Suggested Issue Title:** `Add security headers to Caddy reverse proxy configuration`

---

#### 1.4 DuckDNS Token Exposed in Environment Variable
**Priority:** 🟡 Medium  
**Location:** `docker-compose.yml` (line 35)

**Finding:** The DuckDNS token is passed as an environment variable which can be visible in container inspection.

```yaml
environment:
  - DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
```

**Recommendation:** Consider using Docker secrets or a secrets file mounted at runtime for sensitive values.

**Suggested Issue Title:** `Use Docker secrets for sensitive environment variables`

---

#### 1.5 Git Clone Uses HTTP Instead of Depth-Limited Clone
**Priority:** 🟡 Medium  
**Location:** `infrastructure/cloud-init.yaml` (line 70)

**Finding:** The git clone in cloud-init doesn't use `--depth 1` for faster, minimal clones.

```yaml
- git clone https://github.com/szmyty/theatre.git /opt/theatre/repo
```

**Recommendation:** Use shallow clone: `git clone --depth 1 https://github.com/szmyty/theatre.git /opt/theatre/repo`

**Suggested Issue Title:** `Use shallow git clone in cloud-init for faster provisioning`

---

#### 1.6 Secrets Cleanup Could Be More Thorough
**Priority:** 🟡 Medium  
**Location:** `.github/workflows/deploy_full_stack.yml` (lines 197-203)

**Finding:** The secrets file is deleted after sourcing but before script completion. Consider using trap for guaranteed cleanup.

**Recommendation:**
```bash
cleanup() {
    rm -f /tmp/secrets.env
}
trap cleanup EXIT
```

**Suggested Issue Title:** `Add trap for guaranteed secrets cleanup in provisioning`

---

### 2. Reliability & Error Handling

#### 2.1 Missing Docker Compose Health Checks
**Priority:** 🔴 High  
**Location:** `docker-compose.yml`

**Finding:** Neither Jellyfin nor Caddy containers have health checks defined, making it difficult to determine container readiness.

**Recommendation:** Add health checks:

```yaml
jellyfin:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8096/System/Info/Public"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 60s

caddy:
  healthcheck:
    test: ["CMD", "caddy", "version"]
    interval: 30s
    timeout: 10s
    retries: 3
```

**Suggested Issue Title:** `Add Docker Compose health checks for Jellyfin and Caddy`

---

#### 2.2 gocryptfs Mount Service Missing Timeout
**Priority:** 🟡 Medium  
**Location:** `infrastructure/systemd/gocryptfs-mount.service`

**Finding:** The systemd service lacks a `TimeoutStartSec` which could cause boot hangs if gocryptfs fails.

**Recommendation:** Add timeout configuration:

```ini
[Service]
TimeoutStartSec=60
TimeoutStopSec=30
```

**Suggested Issue Title:** `Add timeout to gocryptfs systemd service`

---

#### 2.3 No Retry Logic for DuckDNS Updates
**Priority:** 🟡 Medium  
**Location:** `scripts/update-duckdns.sh`

**Finding:** The DuckDNS update script doesn't retry on transient failures.

**Recommendation:** Add retry logic:

```bash
MAX_RETRIES=3
for i in $(seq 1 $MAX_RETRIES); do
    response=$(curl --silent --fail --show-error "${url}") && break
    sleep $((i * 5))
done
```

**Suggested Issue Title:** `Add retry logic to DuckDNS update script`

---

#### 2.4 Disk Device Hardcoded in Multiple Locations
**Priority:** 🟡 Medium  
**Location:** `infrastructure/cloud-init.yaml` (line 23), `.github/workflows/deploy_full_stack.yml` (line 259)

**Finding:** The disk device `/dev/sdb` is hardcoded in multiple places, which may not be correct on all VM configurations.

**Recommendation:** Use disk labels or by-id paths: `/dev/disk/by-id/` for more reliable disk identification.

**Suggested Issue Title:** `Use disk labels or by-id paths instead of device names`

---

#### 2.5 Race Condition Between gocryptfs Mount and Docker Start
**Priority:** 🔴 High  
**Location:** `infrastructure/bootstrap.sh`, `docker-compose.yml`

**Finding:** The bootstrap script starts docker-compose before verifying gocryptfs mount is successful, and the systemd ordering relies on correct configuration.

**Recommendation:** Add explicit mount verification before starting containers:

```bash
# In bootstrap.sh, before start_docker_compose:
if ! mountpoint -q "${MOUNT_POINT}"; then
    log "ERROR: gocryptfs mount not active at ${MOUNT_POINT}"
    exit 1
fi
```

**Suggested Issue Title:** `Add explicit mount verification before starting Docker containers`

---

#### 2.6 Missing Network Definition in docker-compose.yml
**Priority:** 🟡 Medium  
**Location:** `docker-compose.yml`

**Finding:** The services rely on Docker's default bridge network. A dedicated network improves isolation and name resolution.

**Recommendation:**

```yaml
networks:
  theatre:
    driver: bridge

services:
  jellyfin:
    networks:
      - theatre
  caddy:
    networks:
      - theatre
```

**Suggested Issue Title:** `Add dedicated Docker network for service isolation`

---

### 3. Code Duplication & Maintainability

#### 3.1 Docker Installation Duplicated
**Priority:** 🟡 Medium  
**Location:** `infrastructure/bootstrap.sh`, `infrastructure/cloud-init.yaml`, `.github/workflows/deploy_full_stack.yml`

**Finding:** Docker installation logic is duplicated in three different places with slightly different approaches.

**Recommendation:** Consolidate Docker installation into a single reusable script that can be called from all locations.

**Suggested Issue Title:** `Consolidate Docker installation into single reusable script`

---

#### 3.2 gocryptfs Setup Duplicated
**Priority:** 🟡 Medium  
**Location:** `infrastructure/bootstrap.sh`, `.github/workflows/deploy_full_stack.yml`

**Finding:** gocryptfs setup logic is duplicated between bootstrap.sh and the GitHub Actions workflow.

**Recommendation:** Extract common provisioning logic into a shared script that both can call.

**Suggested Issue Title:** `Extract common provisioning logic into shared scripts`

---

#### 3.3 Inconsistent Path References
**Priority:** 🟢 Low  
**Location:** Various files  
**Status:** ✅ Fixed

**Finding:** Previously, some files referenced `/srv/library_encrypted` while others used `/mnt/disks/data/.library_encrypted`. This has been standardized.

| File | Path Used |
|------|-----------|
| bootstrap.sh | `/mnt/disks/media/.library_encrypted` |
| common.sh | `/mnt/disks/media/.library_encrypted` (via MOUNT_POINT) |
| deploy_full_stack.yml | `/mnt/disks/media/.library_encrypted` |
| Documentation | `/mnt/disks/media/.library_encrypted` |

**Resolution:** All scripts and documentation now consistently use `/mnt/disks/media/.library_encrypted` as the canonical encrypted directory path.

---

#### 3.4 Environment Variable Names Inconsistent
**Priority:** 🟢 Low  
**Location:** Various files

**Finding:** Some environment variables use different names for the same purpose:
- `passfile` vs `password` for gocryptfs password file
- `GOCRYPTFS_PASSWORD` (secret) vs `GOCRYPTFS_PASSFILE` (file path)

**Recommendation:** Standardize naming convention in documentation and code.

**Suggested Issue Title:** `Standardize environment variable naming conventions`

---

### 4. Documentation & Best Practices

#### 4.1 Missing CONTRIBUTING.md
**Priority:** 🟢 Low  
**Location:** Repository root

**Finding:** No contribution guidelines exist for potential contributors.

**Recommendation:** Add CONTRIBUTING.md with:
- How to set up local development environment
- Code style guidelines
- PR and issue templates
- Testing requirements

**Suggested Issue Title:** `Add CONTRIBUTING.md with development guidelines`

---

#### 4.2 Missing SECURITY.md
**Priority:** 🔴 High  
**Location:** Repository root

**Finding:** No security policy for reporting vulnerabilities.

**Recommendation:** Add SECURITY.md with:
- Supported versions
- How to report vulnerabilities
- Security contact information

**Suggested Issue Title:** `Add SECURITY.md with vulnerability reporting guidelines`

---

#### 4.3 No .editorconfig
**Priority:** 🟢 Low  
**Location:** Repository root

**Finding:** No `.editorconfig` file to ensure consistent formatting across editors.

**Recommendation:** Add `.editorconfig` with standard settings for shell scripts and YAML files.

**Suggested Issue Title:** `Add .editorconfig for consistent code formatting`

---

#### 4.4 Documentation References Old Path
**Priority:** 🟢 Low  
**Location:** `docs/SETUP.md` (line 44)

**Finding:** The SETUP.md document instructs users to not automate mounting, but the project has automated mounting via systemd. This is contradictory.

**Recommendation:** Update documentation to reflect actual project behavior and clarify when manual vs automated mounting is appropriate.

**Suggested Issue Title:** `Update SETUP.md to reflect automated mounting capabilities`

---

### 5. Infrastructure & GCP Optimizations

#### 5.1 No VM Shutdown/Startup Automation
**Priority:** 🟡 Medium  
**Location:** `.github/workflows/`

**Finding:** README mentions "Automatic VM shutdown/startup scheduling" as a planned feature, but there's no implementation or workflow for cost optimization.

**Recommendation:** Add a scheduled workflow to stop VMs during off-hours to reduce costs:

```yaml
on:
  schedule:
    - cron: '0 5 * * *'  # Stop at 5 AM UTC
    - cron: '0 17 * * *' # Start at 5 PM UTC
```

**Suggested Issue Title:** `Add scheduled VM shutdown/startup for cost optimization`

---

#### 5.2 No Resource Limits in docker-compose.yml
**Priority:** 🟡 Medium  
**Location:** `docker-compose.yml`

**Finding:** No memory or CPU limits defined for containers, which could lead to resource exhaustion.

**Recommendation:** For Docker Compose v2 (which this project uses), add resource limits:

```yaml
jellyfin:
  mem_limit: 4g
  cpus: 2.0
  memswap_limit: 4g
```

Note: For Docker Compose v3 with Swarm mode, use `deploy.resources.limits` instead.

**Suggested Issue Title:** `Add resource limits to Docker containers`

---

#### 5.3 Missing GCP Labels for Cost Tracking
**Priority:** 🟢 Low  
**Location:** `.github/workflows/deploy.yml`, `.github/workflows/deploy_full_stack.yml`

**Finding:** No GCP labels are applied to resources for cost tracking and organization.

**Recommendation:** Add labels when creating VM and disk:

```bash
--labels=project=theatre,environment=production
```

**Suggested Issue Title:** `Add GCP labels for resource tracking and cost allocation`

---

#### 5.4 No Backup Strategy Implemented
**Priority:** 🔴 High  
**Location:** N/A

**Finding:** While README mentions backups as planned, there's no implemented backup strategy for:
- Jellyfin configuration
- gocryptfs.conf (master key)
- Media files metadata

**Recommendation:** Implement automated backups using GCP snapshots or gsutil to Cloud Storage.

**Suggested Issue Title:** `Implement automated backup strategy for configurations`

---

### 6. Logging & Monitoring

#### 6.1 No Centralized Logging
**Priority:** 🟡 Medium  
**Location:** N/A

**Finding:** Logs are only stored locally on the VM with no aggregation or alerting.

**Recommendation:** Consider:
- Docker logging driver configuration for structured logs
- Integration with Google Cloud Logging
- Basic log rotation configuration

**Suggested Issue Title:** `Add centralized logging with Google Cloud Logging`

---

#### 6.2 No Monitoring or Alerting
**Priority:** 🟡 Medium  
**Location:** N/A

**Finding:** No monitoring of:
- Disk space (critical for media storage)
- gocryptfs mount status
- Container health
- HTTPS certificate expiration

**Recommendation:** Add basic monitoring script or integrate with Google Cloud Monitoring.

**Suggested Issue Title:** `Add monitoring and alerting for critical system metrics`

---

### 7. Minor Improvements

#### 7.1 Upload Script Missing Progress Indicator
**Priority:** 🟢 Low  
**Location:** `scripts/upload-media.sh`

**Finding:** The upload script uses `scp -C` but doesn't show progress for large file uploads.

**Recommendation:** Add `-v` or progress indicators for user feedback:

```bash
scp -C -o "ControlMaster=auto" -o "ControlPersist=60s" "${local_file}" "${remote_host}:${REMOTE_DIR}/"
```

**Suggested Issue Title:** `Add progress indicator to media upload script`

---

#### 7.2 Missing .dockerignore
**Priority:** 🟢 Low  
**Location:** `config/caddy/`

**Finding:** No `.dockerignore` file in the Caddy build context, which could include unnecessary files.

**Recommendation:** Add `.dockerignore`:

```
README.md
*.md
.git
```

**Suggested Issue Title:** `Add .dockerignore for Caddy build context`

---

#### 7.3 Workflow Permissions Could Be More Restrictive
**Priority:** 🟢 Low  
**Location:** `.github/workflows/deploy.yml`, `.github/workflows/deploy_full_stack.yml`

**Finding:** Both workflows have `contents: read` which is appropriate, but could benefit from explicit security documentation.

**Recommendation:** Add comments explaining why each permission is needed.

**Suggested Issue Title:** `Document workflow permission requirements`

---

## Summary Table

| # | Category | Finding | Priority |
|---|----------|---------|----------|
| 1.1 | Security | Docker images not pinned | 🔴 High |
| 1.2 | Security | Password file creation timing | 🔴 High |
| 1.3 | Security | Missing security headers | 🟡 Medium |
| 1.4 | Security | Token in environment variable | 🟡 Medium |
| 1.5 | Security | Git clone without depth limit | 🟡 Medium |
| 1.6 | Security | Secrets cleanup could use trap | 🟡 Medium |
| 2.1 | Reliability | Missing health checks | 🔴 High |
| 2.2 | Reliability | Service missing timeout | 🟡 Medium |
| 2.3 | Reliability | No retry for DuckDNS | 🟡 Medium |
| 2.4 | Reliability | Hardcoded disk device | 🟡 Medium |
| 2.5 | Reliability | Race condition mount/docker | 🔴 High |
| 2.6 | Reliability | Missing Docker network | 🟡 Medium |
| 3.1 | Maintainability | Docker install duplicated | 🟡 Medium |
| 3.2 | Maintainability | gocryptfs setup duplicated | 🟡 Medium |
| 3.3 | Maintainability | Inconsistent paths | 🟢 Low |
| 3.4 | Maintainability | Inconsistent env var names | 🟢 Low |
| 4.1 | Documentation | Missing CONTRIBUTING.md | 🟢 Low |
| 4.2 | Documentation | Missing SECURITY.md | 🔴 High |
| 4.3 | Documentation | Missing .editorconfig | 🟢 Low |
| 4.4 | Documentation | Contradictory mounting docs | 🟢 Low |
| 5.1 | GCP | No VM scheduling | 🟡 Medium |
| 5.2 | GCP | No resource limits | 🟡 Medium |
| 5.3 | GCP | Missing labels | 🟢 Low |
| 5.4 | GCP | No backup strategy | 🔴 High |
| 6.1 | Monitoring | No centralized logging | 🟡 Medium |
| 6.2 | Monitoring | No monitoring/alerting | 🟡 Medium |
| 7.1 | Minor | Upload progress indicator | 🟢 Low |
| 7.2 | Minor | Missing .dockerignore | 🟢 Low |
| 7.3 | Minor | Workflow permission docs | 🟢 Low |

---

## Suggested Follow-Up GitHub Issues

### High Priority
1. `Pin Docker images to specific versions for reproducible builds`
2. `Improve atomic password file creation in provisioning script`
3. `Add Docker Compose health checks for Jellyfin and Caddy`
4. `Add explicit mount verification before starting Docker containers`
5. `Add SECURITY.md with vulnerability reporting guidelines`
6. `Implement automated backup strategy for configurations`

### Medium Priority
7. `Add security headers to Caddy reverse proxy configuration`
8. `Use Docker secrets for sensitive environment variables`
9. `Use shallow git clone in cloud-init for faster provisioning`
10. `Add trap for guaranteed secrets cleanup in provisioning`
11. `Add timeout to gocryptfs systemd service`
12. `Add retry logic to DuckDNS update script`
13. `Use disk labels or by-id paths instead of device names`
14. `Add dedicated Docker network for service isolation`
15. `Consolidate Docker installation into single reusable script`
16. `Extract common provisioning logic into shared scripts`
17. `Add scheduled VM shutdown/startup for cost optimization`
18. `Add resource limits to Docker containers`
19. `Add centralized logging with Google Cloud Logging`
20. `Add monitoring and alerting for critical system metrics`

### Low Priority
21. ~~`Standardize encrypted directory path across all configurations`~~ (Fixed)
22. `Standardize environment variable naming conventions`
23. `Add CONTRIBUTING.md with development guidelines`
24. `Add .editorconfig for consistent code formatting`
25. `Update SETUP.md to reflect automated mounting capabilities`
26. `Add GCP labels for resource tracking and cost allocation`
27. `Add progress indicator to media upload script`
28. `Add .dockerignore for Caddy build context`
29. `Document workflow permission requirements`

---

## Conclusion

The Theatre project demonstrates strong foundational security practices and a well-organized codebase. The main areas requiring attention are:

1. **Security hardening** - Image pinning, security headers, improved secrets management
2. **Reliability improvements** - Health checks, mount verification, retry logic
3. **Operational readiness** - Backups, monitoring, cost optimization
4. **Maintainability** - Reducing code duplication, standardizing configurations

Addressing the high-priority items should be the immediate focus, followed by medium-priority improvements for production readiness.
