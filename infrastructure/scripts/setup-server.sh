#!/bin/bash
# <UDF name="git_repo" label="Git Repository URL" default="" example="https://github.com/your-org/repo.git" />
# <UDF name="git_branch" label="Git Branch" default="main" example="main" />
# <UDF name="domain" label="Domain Name" default="ai.fame.support" example="ai.fame.support" />

# Enable error reporting and logging
set -e
set -o pipefail

# Log all output to a file for debugging
LOG_FILE="/var/log/fameliza-setup.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Error handler
error_handler() {
  echo "ERROR: Script failed at line $1" >&2
  echo "Check $LOG_FILE for details" >&2
  exit 1
}
trap 'error_handler $LINENO' ERR

# Variables from StackScript data
# Linode StackScript variables from stackscript_data are passed as lowercase env vars
# UDF variables can also be accessed directly
GIT_REPO="${git_repo:-${GIT_REPO:-${UDF_GIT_REPO:-}}}"
GIT_BRANCH="${git_branch:-${GIT_BRANCH:-${UDF_GIT_BRANCH:-main}}}"
DOMAIN="${domain:-${DOMAIN:-${UDF_DOMAIN:-ai.fame.support}}}"

# Log script start
echo "=== Fameliza Server Setup Script Starting ==="
echo "Timestamp: $(date)"
echo "Running as user: $(whoami)"
echo "UID: $(id -u)"
echo "GIT_REPO: ${GIT_REPO}"
echo "GIT_BRANCH: ${GIT_BRANCH}"
echo "DOMAIN: ${DOMAIN}"
echo "=============================================="

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install essential packages
apt-get install -y \
  curl \
  git \
  ufw \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release

# Install Docker
if ! command -v docker &> /dev/null; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
fi

# Install Docker Compose (standalone)
if ! command -v docker-compose &> /dev/null; then
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# Install Bun
if ! command -v bun &> /dev/null; then
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
  echo 'export PATH="$HOME/.bun/bin:$PATH"' >> /root/.bashrc
fi

# Install Caddy
if ! command -v caddy &> /dev/null; then
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
fi

# Create application user
echo "Creating fameliza user..."
if ! id -u fameliza &> /dev/null; then
  # Create user with home directory and group
  useradd -m -s /bin/bash -U fameliza || {
    echo "Failed to create fameliza user" >&2
    exit 1
  }
  usermod -aG docker fameliza || {
    echo "Failed to add fameliza to docker group" >&2
    exit 1
  }
  
  # Verify user was created
  if ! id -u fameliza &> /dev/null; then
    echo "ERROR: fameliza user was not created successfully" >&2
    exit 1
  fi
  
  echo "fameliza user created successfully"
  
  # Setup SSH access for fameliza user
  mkdir -p /home/fameliza/.ssh
  chmod 700 /home/fameliza/.ssh
  
  # Copy root's authorized_keys to fameliza user (if root has keys)
  if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/fameliza/.ssh/authorized_keys
    chmod 600 /home/fameliza/.ssh/authorized_keys
    chown -R fameliza:fameliza /home/fameliza/.ssh
    echo "SSH keys copied to fameliza user"
  else
    echo "Warning: /root/.ssh/authorized_keys not found, SSH keys not copied"
  fi
else
  echo "fameliza user already exists"
  # User exists, but ensure SSH keys are set up
  if [ ! -d /home/fameliza/.ssh ]; then
    mkdir -p /home/fameliza/.ssh
    chmod 700 /home/fameliza/.ssh
  fi
  
  # Copy root's authorized_keys if fameliza doesn't have keys yet
  if [ -f /root/.ssh/authorized_keys ] && [ ! -f /home/fameliza/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/fameliza/.ssh/authorized_keys
    chmod 600 /home/fameliza/.ssh/authorized_keys
    chown -R fameliza:fameliza /home/fameliza/.ssh
    echo "SSH keys copied to fameliza user"
  fi
fi

# Verify user and home directory exist
if [ ! -d /home/fameliza ]; then
  echo "ERROR: /home/fameliza directory was not created" >&2
  exit 1
fi

echo "fameliza user setup complete: $(id fameliza)"

# Create application directory with proper permissions
# Note: This must happen AFTER user creation
APP_DIR="/opt/fameliza"
mkdir -p "$APP_DIR"
# Only chown if fameliza user exists
if id -u fameliza &> /dev/null; then
  chown -R fameliza:fameliza "$APP_DIR"
  chmod 755 "$APP_DIR"
else
  echo "ERROR: Cannot set permissions - fameliza user does not exist" >&2
  exit 1
fi

# Setup firewall
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp

# Create Caddy directory and config
mkdir -p /etc/caddy
mkdir -p /var/www/caddy

# Create Caddyfile (will be replaced by deployment)
cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    reverse_proxy localhost:3000
}
EOF

# Enable and start Caddy
systemctl enable caddy
systemctl restart caddy

# Create systemd service for application (optional, if not using docker-compose)
cat > /etc/systemd/system/fameliza.service <<EOF
[Unit]
Description=Fameliza ElizaOS Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/docker-compose -f ${APP_DIR}/docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker-compose -f ${APP_DIR}/docker-compose.prod.yml down
User=fameliza
Group=fameliza

[Install]
WantedBy=multi-user.target
EOF

# Ensure app directory permissions are correct before cloning
chown -R fameliza:fameliza "$APP_DIR" 2>/dev/null || true
chmod 755 "$APP_DIR"

# Clone repository if provided
if [ -n "$GIT_REPO" ]; then
  if [ ! -d "$APP_DIR/.git" ]; then
    sudo -u fameliza git clone -b "$GIT_BRANCH" "$GIT_REPO" "$APP_DIR"
    # Ensure all cloned files are owned by fameliza
    chown -R fameliza:fameliza "$APP_DIR"
  else
    # If repo exists, ensure permissions are correct
    chown -R fameliza:fameliza "$APP_DIR"
  fi
fi

# Set permissions for PostgreSQL data directory
mkdir -p /var/lib/postgresql/data
chown -R 999:999 /var/lib/postgresql/data 2>/dev/null || true

echo ""
echo "=== Server setup complete! ==="
echo "Setup log saved to: $LOG_FILE"
echo ""
echo "Verification:"
echo "  - fameliza user: $(id fameliza 2>/dev/null || echo 'NOT FOUND')"
echo "  - /home/fameliza exists: $([ -d /home/fameliza ] && echo 'YES' || echo 'NO')"
echo "  - /opt/fameliza exists: $([ -d $APP_DIR ] && echo 'YES' || echo 'NO')"
echo "  - Docker installed: $(command -v docker &>/dev/null && echo 'YES' || echo 'NO')"
echo ""
echo "Next steps:"
echo "1. Configure environment variables in ${APP_DIR}/.env"
echo "2. Run: cd ${APP_DIR} && docker-compose -f docker-compose.prod.yml up -d"
echo ""


