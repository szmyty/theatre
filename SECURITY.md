# Security Policy

## Supported Versions

The following versions of this project are currently supported with security updates:

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |

Only the latest version on the main branch receives security updates. We recommend always using the most recent version.

## Reporting a Vulnerability

We take the security of this project seriously. If you discover a security vulnerability, please follow these steps:

### How to Report

1. **Do not** open a public issue for security vulnerabilities
2. Report security issues via [GitHub Security Advisories](https://github.com/szmyty/theatre/security/advisories/new)
3. Include the following information in your report:
   - Description of the vulnerability
   - Steps to reproduce the issue
   - Potential impact of the vulnerability
   - Any suggested fixes (if applicable)

### Contact Information

- **Maintainer**: Alan Szmyt
- **Reporting Channel**: [GitHub Security Advisories](https://github.com/szmyty/theatre/security/advisories/new)

### What to Expect

- **Acknowledgment**: We will acknowledge receipt of your report within 48 hours
- **Assessment**: We will investigate and assess the vulnerability within 7 days
- **Resolution**: We aim to resolve critical vulnerabilities within 30 days
- **Communication**: We will keep you informed of our progress throughout the process

## Responsible Disclosure Policy

We follow responsible disclosure principles:

1. **Confidentiality**: Please keep the vulnerability confidential until we have released a fix
2. **Good Faith**: We ask that you act in good faith and do not access or modify data that does not belong to you
3. **No Exploitation**: Do not exploit the vulnerability beyond what is necessary to demonstrate the issue
4. **Cooperation**: Work with us to address the issue before any public disclosure
5. **Credit**: We will acknowledge your contribution in the security advisory (unless you prefer to remain anonymous)

## Security Best Practices for Deployment

When deploying this project, please ensure:

- Keep all dependencies up to date
- Use strong, unique passwords for gocryptfs encryption
- Enable HTTPS and ensure TLS certificates are valid
- Restrict network access to trusted sources
- Regularly backup encrypted data
- Monitor system logs for suspicious activity

## Security Features

This project includes several security features:

- **Encryption at Rest**: Media files are encrypted using gocryptfs with AES-256-GCM
- **Encryption in Transit**: All traffic is encrypted via HTTPS using Let's Encrypt certificates
- **Read-Only Access**: Jellyfin mounts media as read-only to prevent modifications
- **Automated Updates**: Dependabot is configured for automatic dependency updates

Thank you for helping keep this project secure!
