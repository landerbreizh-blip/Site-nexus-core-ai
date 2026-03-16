// src/app.js
// =====================================================
// NEXUS CORE AI — Express App Configuration v1.1
// Fixes:
//  - CORS: origins com trim() para evitar rejeição por espaço
//  - Webhooks: nota de autenticação de assinatura
//  - Melhor tratamento de erros de validação (express-validator)
// =====================================================

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const logger = require('./config/logger');

// ── Routes ────────────────────────────────────────────
const authRoutes         = require('./routes/auth.routes');
const leadRoutes         = require('./routes/lead.routes');
const diagnosticRoutes   = require('./routes/diagnostic.routes');
const analyticsRoutes    = require('./routes/analytics.routes');
const organizationRoutes = require('./routes/organization.routes');
const conversationRoutes = require('./routes/conversation.routes');
const webhookRoutes      = require('./routes/webhook.routes');

const app = express();

// ── Segurança ─────────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc:  ["'self'"],
      styleSrc:   ["'self'", "'unsafe-inline'"],
      imgSrc:     ["'self'", 'data:', 'https:'],
    },
  },
  crossOriginEmbedderPolicy: false,
  // HSTS apenas em produção (evita loops em dev com HTTP)
  hsts: process.env.NODE_ENV === 'production'
    ? { maxAge: 31536000, includeSubDomains: true }
    : false,
}));

// ── CORS ──────────────────────────────────────────────
// FIX: .split(',') + .map(trim) evita rejeição de origens com espaço
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    // Permite requisições sem origin (ex: curl, Postman em dev)
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes(origin)) return callback(null, true);
    const err = new Error(`CORS bloqueado: origem ${origin} não permitida`);
    err.status = 403;
    callback(err);
  },
  methods:        ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key', 'X-Webhook-Signature'],
  credentials: true,
  maxAge: 86400, // cache preflight 24h
}));

// ── Rate Limiting ─────────────────────────────────────
const globalLimiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15 min
  max:      parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100,
  standardHeaders: true,
  legacyHeaders:   false,
  message: { success: false, error: 'Muitas requisições. Tente novamente em alguns minutos.' },
  // Identifica cliente por IP real mesmo atrás de proxy/load balancer
  keyGenerator: (req) => req.headers['x-forwarded-for']?.split(',')[0].trim() || req.ip,
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max:       10,
  message: { success: false, error: 'Muitas tentativas de login. Aguarde 15 minutos.' },
});

// Rate limit mais agressivo para o formulário público de diagnóstico
const diagnosticLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hora
  max:       5,
  message: { success: false, error: 'Muitas solicitações de diagnóstico. Tente novamente em 1 hora.' },
});

app.use('/api/', globalLimiter);
app.use('/api/v1/auth/login',    authLimiter);
app.use('/api/v1/auth/register', authLimiter);
app.use('/api/v1/diagnostics',   diagnosticLimiter);

// ── Body Parsing ──────────────────────────────────────
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ── HTTP Logging ──────────────────────────────────────
const morganFormat = process.env.NODE_ENV === 'production' ? 'combined' : 'dev';
app.use(morgan(morganFormat, {
  stream: { write: (msg) => logger.http(msg.trim()) },
  skip:   (req) => req.url === '/health',
}));

// ── Health Check ──────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({
    status:      'healthy',
    service:     'Nexus Core AI API',
    version:     '1.1.0',
    timestamp:   new Date().toISOString(),
    environment: process.env.NODE_ENV,
    uptime:      Math.floor(process.uptime()),
  });
});

// ── API Routes ────────────────────────────────────────
const API = '/api/v1';
app.use(`${API}/auth`,          authRoutes);
app.use(`${API}/leads`,         leadRoutes);
app.use(`${API}/diagnostics`,   diagnosticRoutes);
app.use(`${API}/analytics`,     analyticsRoutes);
app.use(`${API}/organizations`, organizationRoutes);
app.use(`${API}/conversations`, conversationRoutes);
// NOTA DE SEGURANÇA: webhook.routes.js DEVE validar a assinatura HMAC
// do payload (X-Webhook-Signature) antes de processar qualquer evento
// (ex: WhatsApp Cloud API usa SHA-256, Stripe usa stripe-signature)
app.use(`${API}/webhooks`,      webhookRoutes);

// ── 404 Handler ───────────────────────────────────────
app.use('*', (req, res) => {
  res.status(404).json({
    success: false,
    error:   'Endpoint não encontrado',
    path:    req.originalUrl,
    method:  req.method,
  });
});

// ── Global Error Handler ──────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  // Log detalhado apenas em dev para evitar vazamento de info
  logger.error('Global error handler:', {
    message: err.message,
    stack:   process.env.NODE_ENV !== 'production' ? err.stack : undefined,
    url:     req.originalUrl,
    method:  req.method,
    statusCode: err.statusCode || err.status || 500,
  });

  // CORS error
  if (err.message?.includes('CORS')) {
    return res.status(403).json({ success: false, error: err.message });
  }

  // Express-validator errors (passados via next(err) com array)
  if (Array.isArray(err.errors)) {
    return res.status(422).json({
      success: false,
      error:   'Dados inválidos',
      details: err.errors,
    });
  }

  const statusCode = err.statusCode || err.status || 500;
  res.status(statusCode).json({
    success: false,
    error:   process.env.NODE_ENV === 'production'
      ? 'Erro interno do servidor'
      : err.message,
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
  });
});

module.exports = app;
