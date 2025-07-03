// TODO: Implement log monitoring for Hysteria connections
import { Pool } from 'pg';
import { spawn } from 'child_process';
import { createReadStream } from 'fs';
import { watch } from 'fs';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER || 'hysteria',
  password: process.env.DB_PASS || 'hysteria123',
  database: process.env.DB_NAME || 'hysteriadb',
});

class HysteriaLogMonitor {
  constructor() {
    this.activeConnections = new Map(); // Track active connections
    this.userLimits = new Map(); // Cache user connection limits
  }

  async init() {
    try {
      console.log('Initializing Hysteria Log Monitor...');
      
      // Test database connection
      await pool.query('SELECT 1');
      console.log('Database connection established');
      
      // Load user limits into cache
      await this.loadUserLimits();
      
      // Start monitoring
      this.startMonitoring();
    } catch (error) {
      console.error('Failed to initialize log monitor:', error);
      process.exit(1);
    }
  }

  async loadUserLimits() {
    try {
      const result = await pool.query('SELECT id, limit_conn FROM users WHERE is_active = true');
      this.userLimits.clear();
      result.rows.forEach(row => {
        this.userLimits.set(row.id.toString(), row.limit_conn);
      });
      console.log(`Loaded ${this.userLimits.size} user limits`);
    } catch (error) {
      console.error('Error loading user limits:', error);
    }
  }

  startMonitoring() {
    // Try different log sources
    this.tryJournalctl();
    this.tryLogFile();
  }

  tryJournalctl() {
    console.log('Attempting to monitor via journalctl...');
    
    const journalctl = spawn('journalctl', [
      '-u', 'hysteria-server',
      '-f',
      '--no-pager',
      '-o', 'cat'
    ]);

    journalctl.stdout.on('data', (data) => {
      const lines = data.toString().split('\n');
      lines.forEach(line => this.parseLogLine(line));
    });

    journalctl.stderr.on('data', (data) => {
      console.error('journalctl error:', data.toString());
    });

    journalctl.on('close', (code) => {
      console.log(`journalctl process exited with code ${code}`);
      // Fallback to file monitoring
      setTimeout(() => this.tryLogFile(), 5000);
    });

    journalctl.on('error', (error) => {
      console.log('journalctl not available, falling back to file monitoring');
      this.tryLogFile();
    });
  }

  tryLogFile() {
    const logPath = process.env.HYSTERIA_LOG_PATH || '/var/log/hysteria.log';
    console.log(`Attempting to monitor log file: ${logPath}`);

    try {
      // Watch for file changes
      watch(logPath, { persistent: true }, (eventType, filename) => {
        if (eventType === 'change') {
          this.readLogFile(logPath);
        }
      });

      // Initial read
      this.readLogFile(logPath);
    } catch (error) {
      console.error(`Failed to watch log file ${logPath}:`, error);
      console.log('Log monitoring disabled. You can manually parse logs or configure journalctl.');
    }
  }

  readLogFile(logPath) {
    try {
      const stream = createReadStream(logPath, { encoding: 'utf8' });
      let buffer = '';

      stream.on('data', (chunk) => {
        buffer += chunk;
        const lines = buffer.split('\n');
        buffer = lines.pop(); // Keep incomplete line in buffer

        lines.forEach(line => this.parseLogLine(line));
      });

      stream.on('error', (error) => {
        console.error(`Error reading log file: ${error.message}`);
      });
    } catch (error) {
      console.error(`Failed to read log file: ${error.message}`);
    }
  }

  parseLogLine(line) {
    if (!line.trim()) return;

    try {
      // Parse different log formats
      this.parseConnectionEvent(line);
      this.parseDisconnectionEvent(line);
      this.parseBandwidthEvent(line);
    } catch (error) {
      // Silently ignore parsing errors for malformed lines
    }
  }

  parseConnectionEvent(line) {
    // Example: "2024-01-01 12:00:00 [INFO] New connection from 192.168.1.100:12345 for user_id: 1"
    const connectionMatch = line.match(/New connection from ([\d.]+):(\d+) for user_id: (\d+)/);
    if (connectionMatch) {
      const [, ip, port, userId] = connectionMatch;
      this.handleConnection(userId, ip, port);
      return;
    }

    // Alternative format: "2024-01-01 12:00:00 [INFO] Client connected: 192.168.1.100:12345 (user: example.com)"
    const altMatch = line.match(/Client connected: ([\d.]+):(\d+) \(user: ([^)]+)\)/);
    if (altMatch) {
      const [, ip, port, domain] = altMatch;
      this.handleConnectionByDomain(domain, ip, port);
    }
  }

  parseDisconnectionEvent(line) {
    // Example: "2024-01-01 12:05:00 [INFO] Connection closed from 192.168.1.100:12345 for user_id: 1"
    const disconnectMatch = line.match(/Connection closed from ([\d.]+):(\d+) for user_id: (\d+)/);
    if (disconnectMatch) {
      const [, ip, port, userId] = disconnectMatch;
      this.handleDisconnection(userId, ip, port);
      return;
    }

    // Alternative format: "2024-01-01 12:05:00 [INFO] Client disconnected: 192.168.1.100:12345 (user: example.com)"
    const altMatch = line.match(/Client disconnected: ([\d.]+):(\d+) \(user: ([^)]+)\)/);
    if (altMatch) {
      const [, ip, port, domain] = altMatch;
      this.handleDisconnectionByDomain(domain, ip, port);
    }
  }

  parseBandwidthEvent(line) {
    // Example: "2024-01-01 12:03:00 [INFO] Bandwidth update for user_id: 1, sent: 1024, received: 2048"
    const bandwidthMatch = line.match(/Bandwidth update for user_id: (\d+), sent: (\d+), received: (\d+)/);
    if (bandwidthMatch) {
      const [, userId, sent, received] = bandwidthMatch;
      this.updateBandwidth(userId, parseInt(sent), parseInt(received));
    }
  }

  async handleConnection(userId, ip, port) {
    try {
      // Check connection limit
      const limit = this.userLimits.get(userId);
      if (limit) {
        const activeCount = this.getActiveConnectionCount(userId);
        if (activeCount >= limit) {
          console.log(`User ${userId} has reached connection limit (${limit})`);
          return;
        }
      }

      // Record connection
      const result = await pool.query(
        'INSERT INTO connections (user_id, ip_address, connected_at) VALUES ($1, $2, CURRENT_TIMESTAMP) RETURNING id',
        [userId, ip]
      );

      const connectionId = result.rows[0].id;
      this.activeConnections.set(`${userId}:${ip}:${port}`, connectionId);

      console.log(`Connection recorded: User ${userId} from ${ip}:${port}`);
    } catch (error) {
      console.error('Error recording connection:', error);
    }
  }

  async handleConnectionByDomain(domain, ip, port) {
    try {
      // Find user by domain
      const result = await pool.query('SELECT id FROM users WHERE domain = $1', [domain]);
      if (result.rows.length > 0) {
        const userId = result.rows[0].id;
        await this.handleConnection(userId, ip, port);
      }
    } catch (error) {
      console.error('Error handling connection by domain:', error);
    }
  }

  async handleDisconnection(userId, ip, port) {
    try {
      const connectionKey = `${userId}:${ip}:${port}`;
      const connectionId = this.activeConnections.get(connectionKey);

      if (connectionId) {
        await pool.query(
          'UPDATE connections SET disconnected_at = CURRENT_TIMESTAMP WHERE id = $1',
          [connectionId]
        );

        this.activeConnections.delete(connectionKey);
        console.log(`Disconnection recorded: User ${userId} from ${ip}:${port}`);
      }
    } catch (error) {
      console.error('Error recording disconnection:', error);
    }
  }

  async handleDisconnectionByDomain(domain, ip, port) {
    try {
      const result = await pool.query('SELECT id FROM users WHERE domain = $1', [domain]);
      if (result.rows.length > 0) {
        const userId = result.rows[0].id;
        await this.handleDisconnection(userId, ip, port);
      }
    } catch (error) {
      console.error('Error handling disconnection by domain:', error);
    }
  }

  async updateBandwidth(userId, sent, received) {
    try {
      const connectionKey = Array.from(this.activeConnections.keys())
        .find(key => key.startsWith(`${userId}:`));

      if (connectionKey) {
        const connectionId = this.activeConnections.get(connectionKey);
        await pool.query(
          'UPDATE connections SET bytes_sent = bytes_sent + $1, bytes_received = bytes_received + $2 WHERE id = $3',
          [sent, received, connectionId]
        );
      }
    } catch (error) {
      console.error('Error updating bandwidth:', error);
    }
  }

  getActiveConnectionCount(userId) {
    return Array.from(this.activeConnections.keys())
      .filter(key => key.startsWith(`${userId}:`))
      .length;
  }

  // Periodic tasks
  startPeriodicTasks() {
    // Reload user limits every 5 minutes
    setInterval(() => {
      this.loadUserLimits();
    }, 5 * 60 * 1000);

    // Clean up old connections every hour
    setInterval(() => {
      this.cleanupOldConnections();
    }, 60 * 60 * 1000);
  }

  async cleanupOldConnections() {
    try {
      // Remove connections older than 30 days
      const result = await pool.query(
        'DELETE FROM connections WHERE connected_at < NOW() - INTERVAL \'30 days\''
      );
      if (result.rowCount > 0) {
        console.log(`Cleaned up ${result.rowCount} old connections`);
      }
    } catch (error) {
      console.error('Error cleaning up old connections:', error);
    }
  }
}

// Start the monitor
const monitor = new HysteriaLogMonitor();
monitor.init().then(() => {
  monitor.startPeriodicTasks();
  console.log('Hysteria Log Monitor is running...');
});

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('Shutting down log monitor...');
  await pool.end();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log('Shutting down log monitor...');
  await pool.end();
  process.exit(0);
});
