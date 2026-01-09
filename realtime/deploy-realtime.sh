#!/bin/bash

# Nigeria Renewable Energy Real-Time Map Deployment Script
# Deploys COG server, web interface, and monitoring

set -e

echo "🚀 Deploying Nigeria Renewable Energy Real-Time System..."

# Configuration
REPO_URL="https://github.com/Bayode001/nigeria-renewable-energy.git"
DEPLOY_DIR="/var/www/nigeria-energy"
COG_DIR="/opt/cog-server"
WEB_DIR="/var/www/html/nigeria-energy"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}1. Updating repository...${NC}"
if [ -d "$DEPLOY_DIR" ]; then
    cd "$DEPLOY_DIR"
    git pull origin main
else
    git clone "$REPO_URL" "$DEPLOY_DIR"
    cd "$DEPLOY_DIR"
fi

echo -e "${YELLOW}2. Installing dependencies...${NC}"
npm install --production

echo -e "${YELLOW}3. Setting up COG server...${NC}"
if [ ! -d "$COG_DIR" ]; then
    mkdir -p "$COG_DIR"
fi

# Copy COG configuration
cp "$DEPLOY_DIR/cog-realtime.yml" "$COG_DIR/"
cp "$DEPLOY_DIR/cog-realtime-config.json" "$COG_DIR/"

# Install COG server if not present
if ! command -v cog &> /dev/null; then
    echo "Installing COG server..."
    pip install titiler.core titiler.application rasterio
fi

echo -e "${YELLOW}4. Deploying web interface...${NC}"
mkdir -p "$WEB_DIR"
cp "$DEPLOY_DIR/index-realtime.html" "$WEB_DIR/"
cp "$DEPLOY_DIR/index.html" "$WEB_DIR/static.html"  # Static version

# Update Mapbox token in real-time interface
sed -i "s/YOUR_MAPBOX_ACCESS_TOKEN/$MAPBOX_TOKEN/g" "$WEB_DIR/index-realtime.html"

echo -e "${YELLOW}5. Setting up monitoring...${NC}"
# Create monitoring directory
MONITOR_DIR="/var/log/nigeria-energy"
mkdir -p "$MONITOR_DIR"

# Create logrotate configuration
cat > /etc/logrotate.d/nigeria-energy << EOF
$MONITOR_DIR/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

echo -e "${YELLOW}6. Creating systemd services...${NC}"

# COG Server Service
cat > /etc/systemd/system/cog-realtime.service << EOF
[Unit]
Description=Nigeria Renewable Energy COG Server
After=network.target redis.service

[Service]
Type=simple
User=www-data
WorkingDirectory=$COG_DIR
ExecStart=/usr/local/bin/uvicorn titiler.application.main:app --host 0.0.0.0 --port 8080 --workers 4
Environment="PYTHONPATH=$COG_DIR"
Restart=always
RestartSec=10
StandardOutput=append:$MONITOR_DIR/cog-server.log
StandardError=append:$MONITOR_DIR/cog-server.error.log

[Install]
WantedBy=multi-user.target
EOF

# Data Update Service (runs n8n workflow)
cat > /etc/systemd/system/nigeria-energy-update.service << EOF
[Unit]
Description=Nigeria Renewable Energy Data Update
After=network.target

[Service]
Type=oneshot
User=www-data
WorkingDirectory=$DEPLOY_DIR
ExecStart=/usr/bin/node $DEPLOY_DIR/update-data.js
StandardOutput=append:$MONITOR_DIR/update.log
StandardError=append:$MONITOR_DIR/update.error.log

[Install]
WantedBy=multi-user.target
EOF

# Data Update Timer (runs hourly)
cat > /etc/systemd/system/nigeria-energy-update.timer << EOF
[Unit]
Description=Hourly update of Nigeria energy data

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo -e "${YELLOW}7. Setting up Nginx configuration...${NC}"
cat > /etc/nginx/sites-available/nigeria-energy << EOF
server {
    listen 80;
    server_name energy.nigeria.gov.ng;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name energy.nigeria.gov.ng;
    
    ssl_certificate /etc/letsencrypt/live/energy.nigeria.gov.ng/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/energy.nigeria.gov.ng/privkey.pem;
    
    # Web interface
    location / {
        root $WEB_DIR;
        index index-realtime.html;
        try_files \$uri \$uri/ =404;
    }
    
    # Static version
    location /static {
        alias $WEB_DIR;
        index static.html;
    }
    
    # COG API
    location /cog/ {
        proxy_pass http://localhost:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # API endpoints
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    
    # Status endpoint
    location /status {
        alias $DEPLOY_DIR/status.json;
        add_header Content-Type application/json;
    }
    
    # Logs
    access_log $MONITOR_DIR/nginx-access.log;
    error_log $MONITOR_DIR/nginx-error.log;
}
EOF

ln -sf /etc/nginx/sites-available/nigeria-energy /etc/nginx/sites-enabled/

echo -e "${YELLOW}8. Starting services...${NC}"
systemctl daemon-reload
systemctl enable cog-realtime.service
systemctl enable nigeria-energy-update.timer
systemctl start cog-realtime.service
systemctl start nigeria-energy-update.timer
systemctl reload nginx

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo -e "Services running:"
echo -e "  • Web Interface: https://energy.nigeria.gov.ng"
echo -e "  • COG Server: http://localhost:8080"
echo -e "  • Data Updates: Hourly via systemd timer"
echo -e ""
echo -e "Monitor logs:"
echo -e "  tail -f $MONITOR_DIR/*.log"