const express = require('express');
const cors = require('cors');
const config = require('./config');
const mqttClient = require('./mqttClient');

// Import routes
const feedingRoutes = require('./routes/feeding');
const schedulesRoutes = require('./routes/schedules');
const deviceRoutes = require('./routes/device');
const notificationsRoutes = require('./routes/notifications');

const app = express();

// Middlewares
app.use(cors());
app.use(express.json());

// Request logger
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`[HTTP] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${duration}ms)`);
  });
  next();
});

// API Routes
app.use('/api/feeding', feedingRoutes);
app.use('/api/schedules', schedulesRoutes);
app.use('/api/device', deviceRoutes);
app.use('/api/notifications', notificationsRoutes);

// Health check & Overview
app.get('/health', (req, res) => {
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    mqtt_connected: mqttClient.isMQTTConnected()
  });
});

app.get('/api', (req, res) => {
  res.json({
    name: 'PetFeeder Backend API',
    version: '1.0.0',
    description: 'REST API & MQTT Gateway for Smart Automatic Pet Feeder',
    endpoints: {
      feeding: {
        feed_now: 'POST /api/feeding/feed { portion: number, override: boolean }',
        history: 'GET /api/feeding/history?limit=50',
        clear_history: 'DELETE /api/feeding/history'
      },
      schedules: {
        list: 'GET /api/schedules',
        create: 'POST /api/schedules { name, time, portion_g, days, enabled }',
        update: 'PUT /api/schedules/:id',
        toggle: 'PATCH /api/schedules/:id/toggle',
        delete: 'DELETE /api/schedules/:id'
      },
      device: {
        status: 'GET /api/device/status',
        config: 'GET /api/device/config',
        update_config: 'PUT /api/device/config'
      },
      notifications: {
        list: 'GET /api/notifications',
        mark_read: 'PATCH /api/notifications/:id/read',
        clear: 'DELETE /api/notifications'
      }
    }
  });
});

// Root fallback
app.get('/', (req, res) => {
  res.redirect('/api');
});

// Start Server
app.listen(config.port, '0.0.0.0', () => {
  console.log(`=======================================================`);
  console.log(`🐾 PetFeeder Backend is running at http://localhost:${config.port}`);
  console.log(`📡 REST API Endpoint: http://localhost:${config.port}/api`);
  console.log(`📡 MQTT Broker target: ${config.mqtt.brokerUrl}`);
  console.log(`=======================================================`);

  // Initialize MQTT Gateway
  mqttClient.initMQTT();
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n[Server] Shutting down gracefully...');
  process.exit(0);
});
