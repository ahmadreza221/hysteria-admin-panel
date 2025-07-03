import express from 'express';
import { Pool } from 'pg';
import cors from 'cors';
import dotenv from 'dotenv';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import rateLimit from 'express-rate-limit';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

dotenv.config();

const app = express();

// Middleware
app.use(cors({
  origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  credentials: true
}));
app.use(express.json());

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use(limiter);

// Database connection
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER || 'hysteria',
  password: process.env.DB_PASS || 'hysteria123',
  database: process.env.DB_NAME || 'hysteriadb',
});

// Initialize database tables
const initDatabase = async () => {
  try {
    // Create users table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
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
      )
    `);

    // Create connections table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS connections (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        ip_address INET,
        connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        disconnected_at TIMESTAMP,
        bytes_sent BIGINT DEFAULT 0,
        bytes_received BIGINT DEFAULT 0
      )
    `);

    // Create admin users table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS admin_users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255) UNIQUE NOT NULL,
        username VARCHAR(255) NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Insert default admin user if not exists
    const adminExists = await pool.query('SELECT id FROM admin_users WHERE email = $1', ['assiyaee@gmail.com']);
    if (adminExists.rows.length === 0) {
      const passwordHash = await bcrypt.hash('Ahmad2016', 10);
      await pool.query(
        'INSERT INTO admin_users (email, username, password_hash) VALUES ($1, $2, $3)',
        ['assiyaee@gmail.com', 'Admin', passwordHash]
      );
      console.log('Default admin user created');
    }

    console.log('Database initialized successfully');
  } catch (error) {
    console.error('Database initialization error:', error);
    process.exit(1);
  }
};

// Authentication middleware
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key', (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Invalid token' });
    }
    req.user = user;
    next();
  });
};

// Admin authentication endpoint
app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, username, password } = req.body;

    if (!email || !username || !password) {
      return res.status(400).json({ error: 'Email, username, and password are required' });
    }

    const result = await pool.query(
      'SELECT * FROM admin_users WHERE email = $1 AND username = $2',
      [email, username]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const admin = result.rows[0];
    const validPassword = await bcrypt.compare(password, admin.password_hash);

    if (!validPassword) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { id: admin.id, email: admin.email, username: admin.username },
      process.env.JWT_SECRET || 'your-secret-key',
      { expiresIn: '24h' }
    );

    res.json({
      token,
      user: {
        id: admin.id,
        email: admin.email,
        username: admin.username
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Protected routes
app.use('/api/users', authenticateToken);
app.use('/api/stats', authenticateToken);

// User management endpoints
app.get('/api/users', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM users ORDER BY created_at DESC'
    );
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

app.post('/api/users', async (req, res) => {
  try {
    const {
      domain,
      port = 443,
      password,
      obfs = 'salamander',
      package_name = 'basic',
      expired_at,
      limit_conn = 1,
      is_active = true
    } = req.body;

    if (!domain || !password) {
      return res.status(400).json({ error: 'Domain and password are required' });
    }

    const result = await pool.query(
      `INSERT INTO users (domain, port, password, obfs, package_name, expired_at, limit_conn, is_active)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING *`,
      [domain, port, password, obfs, package_name, expired_at, limit_conn, is_active]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating user:', error);
    res.status(500).json({ error: 'Failed to create user' });
  }
});

app.put('/api/users/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const {
      domain,
      port,
      password,
      obfs,
      package_name,
      expired_at,
      limit_conn,
      is_active
    } = req.body;

    const result = await pool.query(
      `UPDATE users 
       SET domain = COALESCE($1, domain),
           port = COALESCE($2, port),
           password = COALESCE($3, password),
           obfs = COALESCE($4, obfs),
           package_name = COALESCE($5, package_name),
           expired_at = $6,
           limit_conn = COALESCE($7, limit_conn),
           is_active = COALESCE($8, is_active)
       WHERE id = $9
       RETURNING *`,
      [domain, port, password, obfs, package_name, expired_at, limit_conn, is_active, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error updating user:', error);
    res.status(500).json({ error: 'Failed to update user' });
  }
});

app.delete('/api/users/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM users WHERE id = $1 RETURNING *', [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ message: 'User deleted successfully' });
  } catch (error) {
    console.error('Error deleting user:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
});

// Stats endpoint
app.get('/api/stats/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Get connection statistics
    const statsResult = await pool.query(`
      SELECT 
        COUNT(*) as total_connections,
        SUM(bytes_sent) as total_bytes_sent,
        SUM(bytes_received) as total_bytes_received,
        MAX(connected_at) as last_connected
      FROM connections 
      WHERE user_id = $1
    `, [id]);

    // Get recent connections
    const recentConnectionsResult = await pool.query(`
      SELECT * FROM connections 
      WHERE user_id = $1 
      ORDER BY connected_at DESC 
      LIMIT 10
    `, [id]);

    const stats = statsResult.rows[0] || {
      total_connections: 0,
      total_bytes_sent: 0,
      total_bytes_received: 0,
      last_connected: null
    };

    res.json({
      ...stats,
      recent_connections: recentConnectionsResult.rows
    });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

const PORT = process.env.PORT || 3100;

// Initialize database and start server
initDatabase().then(() => {
  app.listen(PORT, () => {
    console.log(`Backend server running on port ${PORT}`);
    console.log(`Health check: http://localhost:${PORT}/api/health`);
  });
}).catch(error => {
  console.error('Failed to initialize database:', error);
  process.exit(1);
});
