# Hysteria v2 Admin Panel

A comprehensive web-based management dashboard for Hysteria v2 VPN server with user management, QR code generation, and real-time connection monitoring.

## 🌟 Features

- **🔐 Secure Admin Login** - Protected dashboard with session management
- **👥 User Management** - Create, edit, delete VPN users with domain-based configuration
- **📱 QR Code Generation** - Generate QR codes for easy mobile client setup
- **📄 Config Downloads** - Download JSON/YAML configuration files
- **📊 Real-time Statistics** - Monitor user connections, bandwidth usage, and connection history
- **⏰ Expiration Control** - Set user expiration dates and connection limits
- **🔒 Connection Limits** - Enforce maximum concurrent connections per user
- **📈 Log Monitoring** - Real-time parsing of Hysteria server logs
- **🌐 IPv6 Support** - Full IPv6 configuration support
- **🐳 Docker Ready** - Complete containerized deployment
- **🚀 One-Command Install** - Automated setup script for Ubuntu/Debian

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │    Backend      │    │   PostgreSQL    │
│   (React)       │◄──►│   (Node.js)     │◄──►│   Database      │
│   Port: 3000    │    │   Port: 3100    │    │   Port: 5432    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │  Log Monitor    │
                       │  (Node.js)      │
                       │  Parses logs    │
                       └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Ubuntu 20.04+ or Debian 11+
- Non-root user with sudo privileges
- Domain name (optional, for production)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/hysteria-admin-panel.git
   cd hysteria-admin-panel
   ```

2. **Run the automated installer:**
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

3. **Access the admin panel:**
   - URL: `http://your-domain:3000` or `http://localhost:3000`
   - Email: `assiyaee@gmail.com`
   - Username: `Admin`
   - Password: `Ahmad2016`

### Manual Installation

If you prefer manual installation:

1. **Install Docker and Docker Compose:**
   ```bash
   # Install Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker $USER

   # Install Docker Compose
   sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
   ```

2. **Configure environment:**
   ```bash
   cp env.example .env
   # Edit .env with your settings
   ```

3. **Start services:**
   ```bash
   docker-compose up -d --build
   ```

## 📋 Configuration

### Environment Variables

Create a `.env` file with the following variables:

```env
# Database Configuration
DB_USER=hysteria
DB_PASS=hysteria123
DB_NAME=hysteriadb

# JWT Secret (Change this in production!)
JWT_SECRET=your-super-secret-jwt-key

# Frontend Configuration
FRONTEND_URL=http://your-domain:3000
VITE_API_BASE=http://your-domain:3100/api

# Log Monitor Configuration
HYSTERIA_LOG_PATH=/var/log/hysteria.log

# Domain Configuration
DOMAIN=your-domain.com
```

### Hysteria Server Configuration

The admin panel generates Hysteria v2 client configurations with the following structure:

```yaml
server: "your-domain.com:443"
protocol: "hysteria2"
up_mbps: 100
down_mbps: 100
ipv6: true
obfs:
  type: "salamander"
  password: "user-password"
auth:
  type: "password"
  password: "user-password"
```

## 🔧 API Endpoints

### Authentication
- `POST /api/auth/login` - Admin login

### User Management
- `GET /api/users` - List all users
- `POST /api/users` - Create new user
- `PUT /api/users/:id` - Update user
- `DELETE /api/users/:id` - Delete user

### Statistics
- `GET /api/stats/:id` - Get user statistics

### Health Check
- `GET /api/health` - Service health status

## 📊 Database Schema

### Users Table
```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  domain VARCHAR(255) NOT NULL,
  port INTEGER NOT NULL DEFAULT 443,
  password VARCHAR(255) NOT NULL,
  obfs VARCHAR(50) NOT NULL DEFAULT 'salamander',
  package_name VARCHAR(50) NOT NULL DEFAULT 'basic',
  expired_at TIMESTAMP,
  limit_conn INTEGER NOT NULL DEFAULT 1,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Connections Table
```sql
CREATE TABLE connections (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  ip_address INET,
  connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  disconnected_at TIMESTAMP,
  bytes_sent BIGINT DEFAULT 0,
  bytes_received BIGINT DEFAULT 0
);
```

## 🔍 Log Monitoring

The log monitor automatically parses Hysteria server logs and updates the database with:

- Connection events (connect/disconnect)
- Bandwidth usage
- IP addresses
- User identification

Supported log formats:
- `journalctl -u hysteria-server`
- `/var/log/hysteria.log`

## 🛡️ Security Features

- **JWT Authentication** - Secure token-based authentication
- **Rate Limiting** - API rate limiting to prevent abuse
- **CORS Protection** - Configured CORS for frontend-backend communication
- **Input Validation** - Server-side validation of all inputs
- **SQL Injection Protection** - Parameterized queries
- **Non-root Containers** - Docker containers run as non-root users

## 🐳 Docker Services

- **frontend** - React application (Nginx)
- **backend** - Node.js API server
- **postgres** - PostgreSQL database
- **log-monitor** - Log parsing service

## 📝 Usage Guide

### Adding Users

1. Click "Add User" in the admin panel
2. Fill in the required fields:
   - **Domain**: Your server domain
   - **Port**: Hysteria server port (usually 443)
   - **Password**: User's authentication password
   - **Obfuscation**: Salamander or None
   - **Package**: Basic, Premium, or VIP
   - **Expires At**: Optional expiration date
   - **Connection Limit**: Maximum concurrent connections
   - **Active**: Enable/disable user

### Generating QR Codes

1. Click the download icon next to any user
2. Scan the QR code with Hysteria client apps
3. Or download the JSON configuration file

### Monitoring Usage

1. Click the eye icon to view user statistics
2. Monitor connection count, bandwidth usage
3. View connection history and timestamps

## 🔧 Management Commands

```bash
# View logs
docker-compose logs -f

# Restart services
docker-compose restart

# Stop all services
docker-compose down

# Update and rebuild
git pull
docker-compose up -d --build

# Backup database
docker-compose exec postgres pg_dump -U hysteria hysteriadb > backup.sql

# Restore database
docker-compose exec -T postgres psql -U hysteria hysteriadb < backup.sql
```

## 🚨 Troubleshooting

### Common Issues

1. **Port already in use:**
   ```bash
   sudo netstat -tulpn | grep :3000
   sudo netstat -tulpn | grep :3100
   ```

2. **Database connection failed:**
   ```bash
   docker-compose logs postgres
   docker-compose logs backend
   ```

3. **Frontend not loading:**
   ```bash
   docker-compose logs frontend
   curl http://localhost:3000/health
   ```

4. **Log monitor not working:**
   ```bash
   docker-compose logs log-monitor
   sudo ls -la /var/log/hysteria.log
   ```

### Log Locations

- **Application logs**: `docker-compose logs [service-name]`
- **Hysteria logs**: `/var/log/hysteria.log`
- **Nginx logs**: Inside frontend container

## 🔄 Updates

To update the admin panel:

```bash
# Pull latest changes
git pull

# Rebuild and restart
docker-compose down
docker-compose up -d --build
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Security Notice

- Change default passwords in production
- Update JWT_SECRET in .env file
- Configure SSL/TLS for production use
- Regularly update dependencies
- Monitor logs for suspicious activity

## 🆘 Support

For support and questions:

- Create an issue on GitHub
- Check the troubleshooting section
- Review the logs for error messages

---

**Made with ❤️ for the Hysteria community**