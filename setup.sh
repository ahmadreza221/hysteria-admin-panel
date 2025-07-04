#!/bin/bash
set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions for progress and status
print_step() {
  local percent=$1
  local message=$2
  echo -ne "[$percent] $message... "
}

print_status() {
  local status=$1
  if [ "$status" -eq 0 ]; then
    echo -e "${GREEN}✔️${NC}"
  else
    echo -e "${RED}❌${NC}"
  fi
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_error() {
  local step=$1
  local log=$2
  echo "[$step] FAILED: $log" >> install_error.log
}

# Step status tracking
declare -A STEP_STATUS
SUCCESS_STEPS=0

# 1. Prompt for user input
print_step "0%" "Prompting for user input"
echo "About to ask for domain..."
read -p "Enter your domain name (e.g. asdasdvpn.asdir.xyz): " DOMAIN
echo "About to ask for repo URL..."
read -p "Enter your GitHub repository URL [https://github.com/ahmadreza221/hysteria-admin-panel.git]: " REPO_URL
REPO_URL=${REPO_URL:-https://github.com/ahmadreza221/hysteria-admin-panel.git}
echo "About to ask for email..."
read -p "Enter your email address for SSL certificate [admin@example.com]: " EMAIL
EMAIL=${EMAIL:-admin@example.com}
echo "About to ask for SSL..."
read -p "Enable SSL with Let's Encrypt? (yes/no) [yes]: " ENABLE_SSL
ENABLE_SSL=${ENABLE_SSL:-yes}
echo "About to ask for frontend port..."
read -p "Enter frontend port [3000]: " FRONTEND_PORT
FRONTEND_PORT=${FRONTEND_PORT:-3000}
echo "About to ask for backend port..."
read -p "Enter backend port [3100]: " BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-3100}
echo "About to ask for extra ports..."
read -p "Enter any additional ports to open (comma separated, optional): " EXTRA_PORTS
STEP_STATUS[Prompt]=0
print_status $?

# 2. Install PostgreSQL on host (automatic, no prompt)
print_step "10%" "Installing PostgreSQL on host"
{
  sudo apt update
  sudo apt install -y postgresql postgresql-contrib
  sudo systemctl enable postgresql
  sudo systemctl start postgresql
  # Create user and database if not exist
  sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='hysteria'" | grep -q 1 || sudo -u postgres psql -c "CREATE USER hysteria WITH PASSWORD 'hysteria123';"
  sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='hysteriadb'" | grep -q 1 || sudo -u postgres psql -c "CREATE DATABASE hysteriadb OWNER hysteria;"
  # Grant privileges
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE hysteriadb TO hysteria;"
  sudo -u postgres psql -c "ALTER USER hysteria CREATEDB;"
} 2>>install_error.log
STEP_STATUS[PostgresHost]=$?
print_status $?

# 3. Install dependencies
print_step "15%" "Installing dependencies"
{
  sudo apt update && sudo apt upgrade -y
  sudo apt install -y git curl nginx ufw
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt install -y nodejs
  curl -fsSL https://get.docker.com | sudo bash
  sudo apt install -y docker-compose
  sudo systemctl enable docker
  sudo systemctl start docker
  if [[ "$ENABLE_SSL" == "yes" ]]; then
    sudo apt install -y certbot python3-certbot-nginx
  fi
} 2>>install_error.log
STEP_STATUS[Dependencies]=$?
print_status $?

# 4. Clone project
print_step "30%" "Cloning repository"
{
  git clone "$REPO_URL"
  REPO_DIR=$(basename "$REPO_URL" .git)
  cd "$REPO_DIR"
} 2>>../install_error.log
STEP_STATUS[Clone]=$?
print_status $?

# 4.5. Frontend dependencies & build
print_step "40%" "Installing frontend dependencies and building"
{
  cd frontend
  sudo apt install -y build-essential
  if [ -f package-lock.json ]; then
    npm ci
  else
    npm install
  fi
  npm run build
  cd ..
} 2>>../install_error.log
STEP_STATUS[Frontend]=$?
print_status $?

# 5. Setup .env
print_step "45%" "Setting up environment variables"
{
    cat > .env << EOF
# Database Configuration
DB_USER=hysteria
DB_PASS=hysteria123
DB_NAME=hysteriadb

# JWT Secret (Change this in production!)
JWT_SECRET=$(openssl rand -hex 32)

# Frontend Configuration
FRONTEND_URL=https://$DOMAIN:$FRONTEND_PORT
VITE_API_BASE=https://$DOMAIN:$BACKEND_PORT/api

# Log Monitor Configuration
HYSTERIA_LOG_PATH=/var/log/hysteria.log

# Domain Configuration
DOMAIN=$DOMAIN
EOF
} 2>>../install_error.log
STEP_STATUS[Env]=$?
print_status $?

# 6. Build and run Docker
print_step "60%" "Building and running Docker containers"
{
  sudo docker-compose up -d --build
} 2>>../install_error.log
STEP_STATUS[Docker]=$?
print_status $?

# 7. Nginx config
print_step "75%" "Configuring Nginx reverse proxy"
{
  sudo tee /etc/nginx/sites-available/hysteria-admin-panel <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:$FRONTEND_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /api/ {
        proxy_pass http://localhost:$BACKEND_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  sudo ln -sf /etc/nginx/sites-available/hysteria-admin-panel /etc/nginx/sites-enabled/hysteria-admin-panel
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t && sudo systemctl reload nginx
} 2>>../install_error.log
STEP_STATUS[Nginx]=$?
print_status $?

# 8. Firewall
print_step "85%" "Configuring firewall"
{
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw allow 5432/tcp  # PostgreSQL port
  sudo ufw allow $FRONTEND_PORT/tcp
  sudo ufw allow $BACKEND_PORT/tcp
  if [[ -n "$EXTRA_PORTS" ]]; then
    IFS=',' read -ra PORTS <<< "$EXTRA_PORTS"
    for port in "${PORTS[@]}"; do
      sudo ufw allow $(echo $port | xargs)/tcp
    done
  fi
        sudo ufw --force enable
} 2>>../install_error.log
STEP_STATUS[Firewall]=$?
print_status $?

# 9. SSL
if [[ "$ENABLE_SSL" == "yes" ]]; then
  print_step "95%" "Obtaining SSL certificate with Let's Encrypt"
  {
    sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"
  } 2>>../install_error.log
  STEP_STATUS[SSL]=$?
  print_status $?
else
  STEP_STATUS[SSL]=0
fi

# Calculate summary
SUCCESS_STEPS=0
for key in "${!STEP_STATUS[@]}"; do
  if [ "${STEP_STATUS[$key]}" -eq 0 ]; then
    ((SUCCESS_STEPS++))
  fi
}
PERCENT=$((SUCCESS_STEPS * 100 / ${#STEP_STATUS[@]}))

# Print summary
echo "\n---------------------------------------------"
echo "Installation summary:"
for key in Prompt PostgresHost Dependencies Clone Env Docker Nginx Firewall SSL; do
  if [[ -n "${STEP_STATUS[$key]+x}" ]]; then
    if [ "${STEP_STATUS[$key]}" -eq 0 ]; then
      echo -e "$key: ${GREEN}Success${NC}"
    else
      echo -e "$key: ${RED}Failed${NC}"
    fi
  fi
}
echo "Overall: $PERCENT% complete"

if [ $PERCENT -lt 100 ]; then
  echo -e "\nSome steps failed. Please check install_error.log for details."
  echo "--- install_error.log ---"
  cat ../install_error.log
fi

# Display final information
print_info "\nSetup complete!"
if [[ "$ENABLE_SSL" == "yes" ]]; then
  print_success "Visit: https://$DOMAIN"
else
  print_success "Visit: http://$DOMAIN"
fi
print_info "Project directory: $REPO_DIR"
print_info "You can manage your containers with: sudo docker-compose [up|down|logs]"
print_info "Default Admin Email: assiyaee@gmail.com | Username: Admin | Password: Ahmad2016"
print_info "Important files: .env, /var/log/hysteria.log, docker-compose.yml"
print_info "Useful commands: docker-compose logs -f, docker-compose down, docker-compose restart, git pull && docker-compose up -d --build"
print_warning "Change default passwords and JWT_SECRET in production. Configure SSL/TLS for production use."
echo "---------------------------------------------"
