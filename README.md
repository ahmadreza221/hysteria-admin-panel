# ⚡️ Hysteria v2 Admin Panel

A powerful, modern web dashboard for managing your Hysteria v2 VPN server — with user management, QR code generation, real-time monitoring, and enterprise-grade security.

```
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  🖥️ Frontend  │⇄  │  🛠️ Backend   │⇄  │  🗄️ Database  │
│   (React)     │    │  (Node.js)    │    │ PostgreSQL    │
│   :3000       │    │   :3100       │    │   :5432       │
└───────────────┘    └───────────────┘    └───────────────┘
         ⇵
   ┌─────────────────────┐
   │  📊 Log Monitor     │
   │  (Node.js)          │
   │  Real-time Parsing  │
   └─────────────────────┘
```

---

## 🌟 Features

- 🔐 **Secure Admin Login** — JWT, session management
- 👥 **User Management** — Add, edit, delete, expire, limit connections
- 📱 **QR Code Generation** — Easy mobile client setup
- 📄 **Config Downloads** — JSON/YAML export
- 📊 **Real-time Stats** — Live user, bandwidth, and connection monitoring
- ⏰ **Expiration Control** — Set user expiry and connection limits
- 🔒 **Connection Limits** — Enforce max concurrent connections
- 📈 **Log Monitoring** — Real-time Hysteria log parsing
- 🌐 **IPv6 Support** — Full dual-stack support
- 🐳 **Docker Ready** — Fully containerized deployment
- 🚀 **One-Command Install** — Automated setup for Ubuntu/Debian
- 🛡️ **Enterprise Security** — Rate limiting, input validation, SQLi/XSS protection, non-root containers

---

## 🏗️ Architecture

- **Frontend:** React (port 3000)
- **Backend:** Node.js/Express (port 3100)
- **Database:** PostgreSQL (port 5432)
- **Log Monitor:** Node.js service for real-time log parsing

---

## 🚀 Quick Start

**Automated Install:**
```bash
git clone https://github.com/ahmadreza221/hysteria-admin-panel.git
cd hysteria-admin-panel
chmod +x setup.sh
./setup.sh
```
- Access: `http(s)://your-domain:3000`
- Default admin:  
  - Email: `assiyaee@gmail.com`  
  - Username: `Admin`  
  - Password: `Ahmad2016`

**Manual Install:**  
1. Install Docker & Docker Compose  
2. `cp env.example .env` and edit your settings  
3. `docker-compose up -d --build`

---

## 📋 Configuration

**.env Example:**
```env
DB_USER=hysteria
DB_PASS=hysteria123
DB_NAME=hysteriadb
JWT_SECRET=your-super-secret-jwt-key
FRONTEND_URL=http://your-domain:3000
VITE_API_BASE=http://your-domain:3100/api
HYSTERIA_LOG_PATH=/var/log/hysteria.log
DOMAIN=your-domain.com
```

---

## 🔧 API Endpoints

- **POST /api/auth/login** — Admin login
- **GET/POST/PUT/DELETE /api/users** — User management
- **GET /api/stats/:id** — User statistics
- **GET /api/health** — Service health

---

## 🛡️ Security

- JWT authentication, rate limiting, input validation
- SQL injection & XSS protection
- HTTPS/SSL auto-setup (Let's Encrypt)
- Audit logging
- Non-root Docker containers

---

## 🐳 Docker Services

- **frontend** — React + Nginx
- **backend** — Node.js API
- **postgres** — PostgreSQL
- **log-monitor** — Log parsing

---

## 📝 Usage Guide

- **Add Users:** Use the dashboard to add, edit, or delete users, set expiration, and connection limits.
- **Generate QR Codes:** One-click QR for mobile clients.
- **Monitor Usage:** Real-time stats, bandwidth, and connection logs.
- **Export Configs:** Download user configs as JSON/YAML.

---

## 📦 Maintenance

- **Update:**  
  `git pull && docker-compose up -d --build`
- **Backup:**  
  `docker-compose exec postgres pg_dump -U hysteria hysteriadb > backup.sql`
- **Restore:**  
  `docker-compose exec -T postgres psql -U hysteria hysteriadb < backup.sql`

---

## 🚨 Troubleshooting

- **Port in use:**  
  `sudo netstat -tulpn | grep :3000`
- **Database issues:**  
  `docker-compose logs postgres`
- **Frontend not loading:**  
  `docker-compose logs frontend`
- **Log monitor issues:**  
  `docker-compose logs log-monitor`

---

## 🤝 Contributing

- Fork, branch, and submit pull requests
- See [CONTRIBUTING.md](CONTRIBUTING.md) for details

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.

---

**Made with ❤️ for the Hysteria community. If you like this project, please ⭐️ star the repo!**