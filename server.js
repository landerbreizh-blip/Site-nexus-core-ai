/**
 * NEXUS CORE AI — Backend Server
 * Express.js + SQLite (better-sqlite3)
 */

const express = require('express');
const Database = require('better-sqlite3');
const path = require('path');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;
const ADMIN_KEY = process.env.ADMIN_KEY || 'nexuscore_admin_2026';

// DB Setup
const DB_DIR = path.join(__dirname, 'data');
if (!fs.existsSync(DB_DIR)) fs.mkdirSync(DB_DIR);
const db = new Database(path.join(DB_DIR, 'nexuscore.db'));

db.exec(`
  CREATE TABLE IF NOT EXISTS leads (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    nome       TEXT NOT NULL,
    email      TEXT NOT NULL,
    telefone   TEXT,
    setor      TEXT NOT NULL,
    status     TEXT DEFAULT 'novo',
    ip         TEXT,
    criado_em  DATETIME DEFAULT CURRENT_TIMESTAMP
  );
  CREATE TABLE IF NOT EXISTS leads_log (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    lead_id   INTEGER,
    evento    TEXT,
    descricao TEXT,
    criado_em DATETIME DEFAULT CURRENT_TIMESTAMP
  );
`);

const stmtInsert = db.prepare('INSERT INTO leads (nome, email, telefone, setor, ip) VALUES (@nome, @email, @telefone, @setor, @ip)');
const stmtLog   = db.prepare('INSERT INTO leads_log (lead_id, evento, descricao) VALUES (@leadId, @evento, @descricao)');
const stmtAll   = db.prepare('SELECT * FROM leads ORDER BY criado_em DESC');
const stmtTotal = db.prepare('SELECT COUNT(*) as c FROM leads');

// Middleware
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: '*' }));
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

const leadsLimiter = rateLimit({ windowMs: 15*60*1000, max: 10 });

function sanitize(s) { return typeof s === 'string' ? s.trim().replace(/<[^>]*>/g,'').substring(0,200) : ''; }
function validEmail(e) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e); }

// Routes
app.get('/health', (_, res) => {
  res.json({ status: 'online', service: 'Nexus Core AI', total_leads: stmtTotal.get().c });
});

app.post('/api/leads', leadsLimiter, (req, res) => {
  const { nome, email, telefone, setor } = req.body;
  const setoresOk = ['imobiliaria','concessionaria','consorcio','juridico','outro'];

  if (!nome || sanitize(nome).length < 2) return res.status(400).json({ error: 'Nome inválido.' });
  if (!email || !validEmail(email))        return res.status(400).json({ error: 'E-mail inválido.' });
  if (!setor || !setoresOk.includes(setor)) return res.status(400).json({ error: 'Setor inválido.' });

  const dup = db.prepare("SELECT id FROM leads WHERE email = ? AND criado_em > datetime('now','-1 day')").get(email.toLowerCase().trim());
  if (dup) return res.status(200).json({ success: true, message: 'Diagnóstico solicitado!', id: dup.id });

  try {
    const r = stmtInsert.run({ nome: sanitize(nome), email: email.toLowerCase().trim(), telefone: sanitize(telefone||''), setor, ip: req.ip || 'unknown' });
    stmtLog.run({ leadId: r.lastInsertRowid, evento: 'lead_criado', descricao: `Setor: ${setor}` });
    console.log(`📥 Lead #${r.lastInsertRowid}: ${sanitize(nome)} | ${setor}`);
    res.status(201).json({ success: true, message: 'Diagnóstico solicitado com sucesso!', id: r.lastInsertRowid });
  } catch (e) {
    console.error('DB error:', e.message);
    res.status(500).json({ error: 'Erro interno. Tente novamente.' });
  }
});

app.get('/api/leads', (req, res) => {
  const key = (req.headers.authorization||'').replace('Bearer ','');
  if (key !== ADMIN_KEY) return res.status(401).json({ error: 'Não autorizado.' });
  const leads = stmtAll.all();
  res.json({ total: leads.length, leads });
});

app.patch('/api/leads/:id/status', (req, res) => {
  const key = (req.headers.authorization||'').replace('Bearer ','');
  if (key !== ADMIN_KEY) return res.status(401).json({ error: 'Não autorizado.' });
  const ok = ['novo','qualificado','em_contato','perdido','fechado'];
  const { status } = req.body;
  if (!ok.includes(status)) return res.status(400).json({ error: 'Status inválido.' });
  const r = db.prepare('UPDATE leads SET status = ? WHERE id = ?').run(status, parseInt(req.params.id));
  if (!r.changes) return res.status(404).json({ error: 'Lead não encontrado.' });
  res.json({ success: true, status });
});

app.get('*', (_, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

app.listen(PORT, () => {
  console.log(`\n🚀 Nexus Core AI em http://localhost:${PORT}`);
  console.log(`📊 Health: http://localhost:${PORT}/health`);
  console.log(`🔐 Admin: Authorization: Bearer ${ADMIN_KEY}\n`);
});

module.exports = app;
