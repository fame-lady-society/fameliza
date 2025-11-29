# Deployment Guide for Fameliza on Linode

This guide walks you through deploying the Fameliza ElizaOS project to a Linode server with automated CI/CD, authentication, and DNS configuration.

## Prerequisites

- A Linode account with API access
- An AWS account with Route53 access for the `fame.support` domain
- A GitHub repository for the project
- A Discord application for OAuth (optional, but required for authentication)

## Table of Contents

1. [Linode Setup](#linode-setup)
2. [Terraform Infrastructure](#terraform-infrastructure)
3. [GitHub Secrets Configuration](#github-secrets-configuration)
4. [AWS Route53 DNS Configuration](#aws-route53-dns-configuration)
5. [Discord OAuth Setup](#discord-oauth-setup)
6. [Environment Variables](#environment-variables)
7. [Initial Deployment](#initial-deployment)
8. [Troubleshooting](#troubleshooting)

## Linode Setup

### 1. Create Linode API Token

1. Log in to your Linode account
2. Navigate to **API Tokens** in your profile settings
3. Click **Create a Personal Access Token**
4. Give it a label (e.g., "Fameliza Deployment")
5. Set expiration (recommended: no expiration for CI/CD)
6. Grant **Read/Write** permissions
7. Copy the token and save it securely (you'll need it for Terraform and GitHub secrets)

### 2. Generate SSH Key Pair

```bash
ssh-keygen -t rsa -b 4096 -C "fameliza-deploy" -f ~/.ssh/fameliza_deploy
```

This creates:

- `~/.ssh/fameliza_deploy` (private key - keep secret)
- `~/.ssh/fameliza_deploy.pub` (public key - use in Terraform)

## Terraform Infrastructure

### 1. Install Terraform

```bash
# On macOS
brew install terraform

# On Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### 2. Configure Terraform Variables

**⚠️ SECURITY WARNING: Never commit `terraform.tfvars` to version control! It contains sensitive secrets like API tokens and passwords. The file is already in `.gitignore`.**

1. Copy the example variables file:

   ```bash
   cp infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars
   ```

2. Edit `infrastructure/terraform/terraform.tfvars` with your values:

   ```hcl
   linode_token     = "your-linode-api-token"  # ⚠️ SECRET - Never commit this file!
   instance_label   = "fameliza"
   region           = "us-east"
   instance_type    = "g6-nanode-2"
   ssh_public_key   = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..." # Content of ~/.ssh/fameliza_deploy.pub
   root_password    = "generate-a-strong-password"  # ⚠️ SECRET - Never commit this file!
   git_repo         = "https://github.com/your-org/fameliza.git"
   git_branch       = "main"
   domain           = "ai.fame.support"
   ```

   **Alternative: Use Environment Variables**

   Instead of using `terraform.tfvars`, you can set sensitive values via environment variables:

   ```bash
   export TF_VAR_linode_token="your-linode-api-token"
   export TF_VAR_root_password="your-strong-password"
   # Then run: terraform apply
   ```

   This way, secrets never touch the filesystem. See [Terraform Environment Variables](https://www.terraform.io/docs/cli/config/environment-variables.html) for more details.

### 3. Initialize and Apply Terraform

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

After applying, Terraform will output:

- `instance_ip`: The public IP address of your Linode instance
- `instance_id`: The Linode instance ID

**Save the instance IP** - you'll need it for DNS configuration.

### 4. Verify Server Setup

SSH into the instance to verify setup:

```bash
# For setup operations, use root
ssh -i ~/.ssh/fameliza_deploy root@<instance_ip>

# For application operations, use fameliza (no sudo access)
ssh -i ~/.ssh/fameliza_deploy fameliza@<instance_ip>
```

You should see Docker, Docker Compose, Bun, and Caddy installed. The `fameliza` user is in the `docker` group, so it can run Docker commands without sudo.

## GitHub Secrets Configuration

Configure the following secrets in your GitHub repository:

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Add the following secrets:

| Secret Name              | Description                                        | Example                                       |
| ------------------------ | -------------------------------------------------- | --------------------------------------------- |
| `LINODE_SSH_PRIVATE_KEY` | Contents of `~/.ssh/fameliza_deploy` (private key) | `-----BEGIN OPENSSH PRIVATE KEY-----...`      |
| `LINODE_HOST`            | Public IP address of your Linode instance          | `192.0.2.1`                                   |
| `LINODE_USER`            | SSH user (defaults to `fameliza` if not set)       | `fameliza` (optional, defaults to `fameliza`) |

## AWS Route53 DNS Configuration

### 1. Access Route53 Console

1. Log in to AWS Console
2. Navigate to **Route53** → **Hosted zones**
3. Select the hosted zone for `fame.support`

### 2. Create A Record

1. Click **Create record**
2. Configure:
   - **Record name**: `ai` (creates `ai.fame.support`)
   - **Record type**: `A`
   - **Value**: The Linode instance IP (from Terraform output)
   - **TTL**: `300` (5 minutes) for faster updates, or `3600` (1 hour) for stability
3. Click **Create records**

### 3. Verify DNS Propagation

Wait a few minutes, then verify:

```bash
dig ai.fame.support +short
# Should return your Linode IP
```

Or use an online tool like [whatsmydns.net](https://www.whatsmydns.net)

## Discord OAuth Setup

### 1. Create Discord Application

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **New Application**
3. Name it (e.g., "Fameliza")
4. Note the **Application ID** (you'll need this)

### 2. Create OAuth2 Credentials

1. In your Discord application, go to **OAuth2**
2. Click **Reset Secret** and copy the **Client Secret**
3. Add redirect URI:
   - **Redirects**: `https://ai.fame.support/auth/discord/callback`
   - Click **Add Redirect**

### 3. Configure Access Control (Optional)

You can restrict access by:

**Option A: Specific User IDs**

- Get user IDs from Discord (enable Developer Mode, right-click user → Copy ID)
- Set `ALLOWED_DISCORD_USER_IDS` environment variable (comma-separated)

**Option B: Guild Roles**

- Get role IDs from your Discord server
- Set `ALLOWED_DISCORD_GUILD_ROLES` environment variable (comma-separated)

## Environment Variables

### 1. Create `.env` File on Server

SSH into your Linode instance as `root` to create the `.env` file (fameliza user doesn't have sudo):

```bash
ssh -i ~/.ssh/fameliza_deploy root@<instance_ip>
cd /opt/fameliza
```

Create `.env` file:

```bash
nano .env
# Or use your preferred editor
```

### 2. Configure Environment Variables

Copy the template from `.env.example` and fill in your values:

```bash
# Database Configuration
# IMPORTANT: When using docker-compose, the hostname is the service name 'postgres', not 'localhost'
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your-secure-password-here
POSTGRES_DB=eliza
# POSTGRES_URL will be auto-constructed from above, or set explicitly:
POSTGRES_URL=postgresql://postgres:your-secure-password@postgres:5432/eliza

# Server Configuration
SERVER_PORT=3000
ELIZA_UI_ENABLE=true
NODE_ENV=production
LOG_LEVEL=info

# Authentication Configuration
DISCORD_CLIENT_ID=your-discord-application-id
DISCORD_CLIENT_SECRET=your-discord-client-secret
DISCORD_CALLBACK_URL=https://ai.fame.support/auth/discord/callback
SESSION_SECRET=generate-a-random-32-character-string
API_KEY_SECRET=generate-another-random-32-character-string

# Access Control (optional)
# ALLOWED_DISCORD_USER_IDS=123456789,987654321
# ALLOWED_DISCORD_GUILD_ROLES=role-id-1,role-id-2

# Core AI Providers (at least one required)
OPENAI_API_KEY=your-openai-api-key
# OR
ANTHROPIC_API_KEY=your-anthropic-api-key

# Other optional variables...
```

**Important**: Generate secure random strings for `SESSION_SECRET` and `API_KEY_SECRET`:

```bash
openssl rand -hex 32
```

After creating the `.env` file, ensure it's owned by fameliza:

```bash
chown fameliza:fameliza /opt/fameliza/.env
```

### 3. Update Caddy Configuration

Copy the Caddyfile to the server (as root):

```bash
cp /opt/fameliza/infrastructure/caddy/Caddyfile /etc/caddy/Caddyfile
systemctl reload caddy
```

## Initial Deployment

### 1. Manual First Deployment

SSH into the server as root for initial setup, then switch to fameliza user for running the app:

```bash
# SSH as root for setup operations
ssh -i ~/.ssh/fameliza_deploy root@<instance_ip>

# Setup: Create app directory and set permissions (as root)
mkdir -p /opt/fameliza
chown -R fameliza:fameliza /opt/fameliza
chmod 755 /opt/fameliza

# Clone repository as fameliza user
sudo -u fameliza bash << 'EOF'
cd /opt/fameliza
git clone https://github.com/fame-lady-society/fameliza.git .
EOF

# Copy Caddyfile (requires root)
cp /opt/fameliza/infrastructure/caddy/Caddyfile /etc/caddy/Caddyfile
systemctl reload caddy

# Switch to fameliza user for running the application
sudo -u fameliza bash << 'EOF'
export PATH="/home/fameliza/.bun/bin:$PATH"
cd /opt/fameliza

# Copy production docker-compose
cp infrastructure/docker-compose.prod.yml docker-compose.prod.yml

# Start services (fameliza user is in docker group, so no sudo needed)
docker-compose -f docker-compose.prod.yml up -d --build

# Check logs
docker-compose -f docker-compose.prod.yml logs -f
EOF
```

**Note**: The `fameliza` user doesn't have sudo access, so use `root` for setup operations. The application itself runs as the `fameliza` user.

### 2. Verify Deployment

1. Check service health:

   ```bash
   docker-compose -f docker-compose.prod.yml ps
   curl https://ai.fame.support/health
   ```

2. Test authentication:

   - Visit `https://ai.fame.support`
   - You should be redirected to Discord OAuth
   - After authentication, you should see the ElizaOS interface

3. Test API with API key:

   ```bash
   # First, get an API key (requires authentication)
   curl -X POST https://ai.fame.support/auth/api-key \
     -H "Cookie: connect.sid=your-session-cookie"

   # Then use the API key
   curl https://ai.fame.support/api/your-endpoint \
     -H "Authorization: Bearer your-api-key"
   ```

### 3. Enable Automated Deployments

Once manual deployment works, future deployments will happen automatically via GitHub Actions when you merge to `main`.

**Note**: The GitHub Actions workflow uses `root` by default (or the user specified in `LINODE_USER` secret) for setup operations, then switches to the `fameliza` user for running the application. This ensures proper permissions while keeping the app running as a non-root user.

## Troubleshooting

**Note**: Most troubleshooting commands should be run as the `fameliza` user (SSH as `fameliza@<instance_ip>`). The `fameliza` user is in the `docker` group, so it can run docker-compose commands without sudo.

### Service Won't Start

```bash
# SSH as fameliza user
ssh -i ~/.ssh/fameliza_deploy fameliza@<instance_ip>
cd /opt/fameliza

# Check Docker logs
docker-compose -f docker-compose.prod.yml logs

# Check individual service
docker-compose -f docker-compose.prod.yml logs elizaos
docker-compose -f docker-compose.prod.yml logs postgres

# Restart services
docker-compose -f docker-compose.prod.yml restart
```

### Database Connection Issues

```bash
# SSH as fameliza user
ssh -i ~/.ssh/fameliza_deploy fameliza@<instance_ip>
cd /opt/fameliza

# Check PostgreSQL is running
docker-compose -f docker-compose.prod.yml ps postgres

# Test connection from host
docker-compose -f docker-compose.prod.yml exec postgres psql -U postgres -d eliza

# Test connection from ElizaOS container
docker-compose -f docker-compose.prod.yml exec elizaos sh -c 'echo $POSTGRES_URL'

# Verify database is accessible from ElizaOS container
docker-compose -f docker-compose.prod.yml exec elizaos sh -c 'nc -zv postgres 5432'

# Check connection string in .env (as root, since fameliza can't read it if permissions are wrong)
ssh -i ~/.ssh/fameliza_deploy root@<instance_ip>
cat /opt/fameliza/.env | grep POSTGRES_URL

# Check database logs (back as fameliza)
ssh -i ~/.ssh/fameliza_deploy fameliza@<instance_ip>
cd /opt/fameliza
docker-compose -f docker-compose.prod.yml logs postgres

# Verify database was created
docker-compose -f docker-compose.prod.yml exec postgres psql -U postgres -l
```

### Authentication Not Working

1. Verify Discord OAuth credentials:

   - Check `DISCORD_CLIENT_ID` and `DISCORD_CLIENT_SECRET` in `.env`
   - Verify redirect URI matches exactly: `https://ai.fame.support/auth/discord/callback`

2. Check session configuration:

   - Ensure `SESSION_SECRET` is set and is a secure random string
   - Verify cookies are being set (check browser DevTools)

3. Check access control:
   - If using `ALLOWED_DISCORD_USER_IDS`, ensure your Discord user ID is included
   - If using `ALLOWED_DISCORD_GUILD_ROLES`, ensure you have the required role

### SSL Certificate Issues

```bash
# Check Caddy logs
sudo journalctl -u caddy -f

# Reload Caddy
sudo systemctl reload caddy

# Verify certificate
curl -vI https://ai.fame.support
```

### GitHub Actions Deployment Fails

1. Check GitHub Actions logs for errors
2. Verify SSH key is correctly set in secrets
3. Test SSH connection manually:
   ```bash
   ssh -i ~/.ssh/fameliza_deploy fameliza@<instance_ip>
   ```
4. Ensure repository is accessible from GitHub Actions

### Rollback Procedure

If a deployment breaks, rollback to previous version:

```bash
# SSH as root, then switch to fameliza for app operations
ssh -i ~/.ssh/fameliza_deploy root@<instance_ip>

sudo -u fameliza bash << 'EOF'
export PATH="/home/fameliza/.bun/bin:$PATH"
cd /opt/fameliza

# Checkout previous commit
git log --oneline
git checkout <previous-commit-hash>

# Rebuild and restart
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.prod.yml up -d --build
EOF
```

## Maintenance

### Updating Environment Variables

1. SSH into server as `root` to edit the file (fameliza user doesn't have sudo):
   ```bash
   ssh -i ~/.ssh/fameliza_deploy root@<instance_ip>
   nano /opt/fameliza/.env
   # Or use your preferred editor
   ```
2. Ensure file is owned by fameliza:
   ```bash
   chown fameliza:fameliza /opt/fameliza/.env
   ```
3. Restart services as fameliza user:
   ```bash
   sudo -u fameliza bash << 'EOF'
   cd /opt/fameliza
   docker-compose -f docker-compose.prod.yml restart elizaos
   EOF
   ```

### Database Backups

```bash
# Create backup
docker-compose -f docker-compose.prod.yml exec postgres pg_dump -U postgres eliza > backup_$(date +%Y%m%d).sql

# Restore backup
docker-compose -f docker-compose.prod.yml exec -T postgres psql -U postgres eliza < backup_20240101.sql

# Backup with compression
docker-compose -f docker-compose.prod.yml exec postgres pg_dump -U postgres -Fc eliza > backup_$(date +%Y%m%d).dump

# Restore compressed backup
docker-compose -f docker-compose.prod.yml exec -T postgres pg_restore -U postgres -d eliza -c backup_20240101.dump
```

### Database Initialization

ElizaOS will automatically initialize the database schema on first connection. The database connection is configured via the `POSTGRES_URL` environment variable:

- **Format**: `postgresql://username:password@host:port/database`
- **Host**: When using docker-compose, use the service name `postgres` (not `localhost`)
- **Port**: Default is `5432`
- **Database**: Default is `eliza`

The database will be automatically created if it doesn't exist, and ElizaOS will create the necessary tables on first startup.

**Important**: The `POSTGRES_URL` in your `.env` file should use `postgres` as the hostname (the Docker service name), not `localhost` or `127.0.0.1`, since the connection is made from within the Docker network.

### Monitoring

**Note**: Run these commands as the `fameliza` user (SSH as `fameliza@<instance_ip>`):

```bash
ssh -i ~/.ssh/fameliza_deploy fameliza@<instance_ip>
cd /opt/fameliza

# Check service status
docker-compose -f docker-compose.prod.yml ps

# View logs
docker-compose -f docker-compose.prod.yml logs -f

# System resources (requires root or sudo access)
ssh -i ~/.ssh/fameliza_deploy root@<instance_ip>
htop
df -h
```

## Security Notes

1. **Never commit `.env` file** - it contains sensitive credentials
2. **Rotate secrets regularly** - especially `SESSION_SECRET` and `API_KEY_SECRET`
3. **Keep SSH keys secure** - use strong passphrases and limit access
4. **Firewall configuration** - only ports 22, 80, 443 should be open
5. **Regular updates** - keep system packages and Docker images updated

## Support

For issues specific to:

- **ElizaOS**: Check [ElizaOS documentation](https://elizaos.github.io)
- **Linode**: Check [Linode documentation](https://www.linode.com/docs)
- **Terraform**: Check [Terraform documentation](https://www.terraform.io/docs)
