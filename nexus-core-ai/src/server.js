// src/server.js
// =====================================================
// NEXUS CORE AI — Main Server Entry Point v1.1
// Fixes:
//  - Valida variáveis de ambiente obrigatórias antes de iniciar
//  - Graceful shutdown com timeout configurável
//  - Keep-alive timeout acima do load balancer (recomendado para AWS/GCP)
// =====================================================

require('dotenv').config();

// ── Validação de variáveis de ambiente obrigatórias ───
// Verifica ANTES de importar outros módulos para falhar rápido e com mensagem clara
const REQUIRED_ENV = [
  'DATABASE_URL',
  'JWT_SECRET',
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
];

const missingEnv = REQUIRED_ENV.filter((key) => !process.env[key]);
if (missingEnv.length > 0) {
  console.error('❌ ERRO: Variáveis de ambiente obrigatórias ausentes:');
  missingEnv.forEach((key) => console.error(`   → ${key}`));
  console.error('   Configure o arquivo .env antes de iniciar o servidor.');
  process.exit(1);
}

// Avisa sobre variáveis recomendadas (não bloqueia)
const RECOMMENDED_ENV = ['ALLOWED_ORIGINS', 'RATE_LIMIT_MAX_REQUESTS', 'NODE_ENV'];
RECOMMENDED_ENV.forEach((key) => {
  if (!process.env[key]) {
    console.warn(`⚠️  Variável de ambiente recomendada não definida: ${key}`);
  }
});

const app            = require('./app');
const logger         = require('./config/logger');
const { testConnection } = require('./config/database');

const PORT = parseInt(process.env.PORT, 10) || 3000;
const SHUTDOWN_TIMEOUT = parseInt(process.env.SHUTDOWN_TIMEOUT_MS, 10) || 10_000;

const startServer = async () => {
  // 1. Testa conexão com banco de dados
  const dbOk = await testConnection();
  if (!dbOk) {
    if (process.env.NODE_ENV === 'production') {
      logger.error('❌ Banco indisponível em produção — abortando inicialização');
      process.exit(1);
    } else {
      logger.warn('⚠️  Banco indisponível — continuando em modo de desenvolvimento sem DB');
    }
  }

  // 2. Inicia o servidor HTTP
  const server = app.listen(PORT, () => {
    logger.info(`🚀 Nexus Core AI API rodando na porta ${PORT}`);
    logger.info(`🌍 Ambiente: ${process.env.NODE_ENV || 'development'}`);
    logger.info(`📡 Versão da API: /api/v1`);
    if (process.env.NODE_ENV !== 'production') {
      logger.info(`🔗 http://localhost:${PORT}/health`);
    }
  });

  // FIX: keep-alive maior que o timeout do load balancer (padrão AWS ALB = 60s)
  // Evita erros 502 em produção por conexão encerrada prematuramente
  server.keepAliveTimeout = 65_000;
  server.headersTimeout   = 66_000;

  // 3. Graceful shutdown
  let shuttingDown = false;

  const shutdown = (signal) => {
    if (shuttingDown) return;
    shuttingDown = true;

    logger.info(`⚠️  ${signal} recebido — encerrando servidor graciosamente...`);

    server.close(() => {
      logger.info('✅ Servidor HTTP encerrado. Encerrando processo...');
      process.exit(0);
    });

    // Força encerramento após timeout
    setTimeout(() => {
      logger.error(`❌ Graceful shutdown excedeu ${SHUTDOWN_TIMEOUT}ms — forçando encerramento`);
      process.exit(1);
    }, SHUTDOWN_TIMEOUT).unref(); // .unref() não bloqueia o event loop
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT',  () => shutdown('SIGINT'));

  // 4. Tratamento de erros não capturados
  process.on('unhandledRejection', (reason, promise) => {
    logger.error('Unhandled Promise Rejection:', {
      reason: reason instanceof Error ? reason.message : reason,
      stack:  reason instanceof Error ? reason.stack  : undefined,
      promise,
    });
    // Em produção, encerra o processo para que o orquestrador reinicie
    if (process.env.NODE_ENV === 'production') {
      shutdown('unhandledRejection');
    }
  });

  process.on('uncaughtException', (error) => {
    logger.error('Uncaught Exception — encerrando por segurança:', {
      message: error.message,
      stack:   error.stack,
    });
    process.exit(1);
  });

  return server;
};

startServer().catch((err) => {
  console.error('❌ Falha crítica ao iniciar servidor:', err);
  process.exit(1);
});
