#!/bin/bash
set -e

# Prompt for domain
read -p "Enter your domain name (e.g. asdasdvpn.asdir.xyz): " DOMAIN

# Prompt for GitHub repository URL
read -p "Enter your GitHub repository URL [https://github.com/ahmadreza221/hysteria-admin-panel.git]: " REPO_URL
REPO_URL=${REPO_URL:-https://github.com/ahmadreza221/hysteria-admin-panel.git}

# Prompt for SSL
read -p "Enable SSL with Let's Encrypt? (yes/no) [no]: " ENABLE_SSL
ENABLE_SSL=${ENABLE_SSL:-no}

# Update and install dependencies
echo "Updating system and installing dependencies..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl nginx ufw

# Install Node.js (LTS)
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# Install Docker & Docker Compose
curl -fsSL https://get.docker.com | sudo bash
sudo apt install -y docker-compose
sudo systemctl enable docker
sudo systemctl start docker

# Install certbot if SSL is enabled
if [[ "$ENABLE_SSL" == "yes" ]]; then
  sudo apt install -y certbot python3-certbot-nginx
fi

# Clone project
echo "Cloning project from $REPO_URL ..."
git clone "$REPO_URL"
REPO_DIR=$(basename "$REPO_URL" .git)
cd "$REPO_DIR"

# Copy and update .env
cp env.example .env
sed -i "s|^DOMAIN=.*|DOMAIN=$DOMAIN|g" .env
sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=https://$DOMAIN|g" .env
sed -i "s|^VITE_API_BASE=.*|VITE_API_BASE=https://$DOMAIN/api|g" .env

# Build and run with Docker Compose
echo "Building and running Docker containers..."
sudo docker-compose up -d --build

# Nginx config for reverse proxy (IPv6 only)
echo "Configuring Nginx reverse proxy..."
sudo tee /etc/nginx/sites-available/hysteria-admin-panel <<EOF
server {
    listen [::]:80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://[::1]:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /api/ {
        proxy_pass http://[::1]:3100/;
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

# Firewall settings
echo "Configuring firewall..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3000/tcp
sudo ufw allow 3100/tcp
sudo ufw --force enable

# SSL with Let's Encrypt
if [[ "$ENABLE_SSL" == "yes" ]]; then
  echo "Obtaining SSL certificate with Let's Encrypt..."
  sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m your-email@example.com
fi

echo "---------------------------------------------"
echo "Setup complete!"
if [[ "$ENABLE_SSL" == "yes" ]]; then
  echo "Visit: https://$DOMAIN"
else
  echo "Visit: http://$DOMAIN"
fi
echo "Project directory: $REPO_DIR"
echo "You can manage your containers with: sudo docker-compose [up|down|logs]"
echo "---------------------------------------------" 