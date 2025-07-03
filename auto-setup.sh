#!/bin/bash
set -e

# Helper functions for progress and status
print_step() {
  local percent=$1
  local message=$2
  echo -ne "[$percent] $message... "
}

print_status() {
  local status=$1
  if [ "$status" -eq 0 ]; then
    echo -e "\033[32m✔️\033[0m"
  else
    echo -e "\033[31m❌\033[0m"
  fi
}

log_error() {
  local step=$1
  local log=$2
  echo "[$step] FAILED: $log" >> install_error.log
}

# Step status tracking
declare -A STEP_STATUS
TOTAL_STEPS=7
SUCCESS_STEPS=0

# 1. Prompt for user input
print_step "0%" "Prompting for user input"
{
  read -p "Enter your domain name (e.g. asdasdvpn.asdir.xyz): " DOMAIN
  read -p "Enter your GitHub repository URL [https://github.com/ahmadreza221/hysteria-admin-panel.git]: " REPO_URL
  REPO_URL=${REPO_URL:-https://github.com/ahmadreza221/hysteria-admin-panel.git}
  read -p "Enter your email address for SSL certificate [admin@example.com]: " EMAIL
  EMAIL=${EMAIL:-admin@example.com}
  read -p "Enable SSL with Let's Encrypt? (yes/no) [yes]: " ENABLE_SSL
  ENABLE_SSL=${ENABLE_SSL:-yes}
  read -p "Enter frontend port [3000]: " FRONTEND_PORT
  FRONTEND_PORT=${FRONTEND_PORT:-3000}
  read -p "Enter backend port [3100]: " BACKEND_PORT
  BACKEND_PORT=${BACKEND_PORT:-3100}
  read -p "Enter any additional ports to open (comma separated, optional): " EXTRA_PORTS
} 2>>install_error.log
STEP_STATUS[Prompt]=0
print_status $?

# 2. Install dependencies
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

# 3. Clone project
print_step "30%" "Cloning repository"
{
  git clone "$REPO_URL"
  REPO_DIR=$(basename "$REPO_URL" .git)
  cd "$REPO_DIR"
} 2>>../install_error.log
STEP_STATUS[Clone]=$?
print_status $?

# 4. Setup .env
print_step "45%" "Setting up environment variables"
{
  cp env.example .env
  sed -i "s|^DOMAIN=.*|DOMAIN=$DOMAIN|g" .env
  sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=https://$DOMAIN|g" .env
  sed -i "s|^VITE_API_BASE=.*|VITE_API_BASE=https://$DOMAIN/api|g" .env
} 2>>../install_error.log
STEP_STATUS[Env]=$?
print_status $?

# 5. Build and run Docker
print_step "60%" "Building and running Docker containers"
{
  sudo docker-compose up -d --build
} 2>>../install_error.log
STEP_STATUS[Docker]=$?
print_status $?

# 6. Nginx config
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

# 7. Firewall
print_step "85%" "Configuring firewall"
{
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
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

# 8. SSL
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
for key in Prompt Dependencies Clone Env Docker Nginx Firewall SSL; do
  if [[ -n "${STEP_STATUS[$key]+x}" ]]; then
    if [ "${STEP_STATUS[$key]}" -eq 0 ]; then
      echo -e "$key: \033[32mSuccess\033[0m"
    else
      echo -e "$key: \033[31mFailed\033[0m"
    fi
  fi
}
echo "Overall: $PERCENT% complete"

if [ $PERCENT -lt 100 ]; then
  echo -e "\nSome steps failed. Please check install_error.log for details."
  echo "--- install_error.log ---"
  cat ../install_error.log
fi

echo "\nSetup complete!"
echo "If all steps are green, visit: http${ENABLE_SSL:+s}://$DOMAIN"
echo "Project directory: $REPO_DIR"
echo "You can manage your containers with: sudo docker-compose [up|down|logs]"
echo "---------------------------------------------" 