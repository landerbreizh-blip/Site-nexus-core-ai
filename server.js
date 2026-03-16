// src/server.js
// =====================================================
// NEXUS CORE AI — Main Server Entry Point
// =====================================================

require('dotenv').config();
const app = require('./app');
const logger = require('./config/logger');
const { testConnection } = require('./config/database');

const PORT = process.env.PORT || 3000;

const startServer = async () => {
  // 1. Testa conexão com banco
  const dbOk = await testConnection();
  if (!dbOk && process.env.NODE_ENV === 'production') {
    logger.error('❌ Banco indisponível — abortando inicialização');
    process.exit(1);
  }

  // 2. Inicia o servidor HTTP
  const server = app.listen(PORT, () => {
    logger.info(`🚀 Nexus Core AI API rodando na porta ${PORT}`);
    logger.info(`🌍 Ambiente: ${process.env.NODE_ENV}`);
    logger.info(`📡 Versão: /api/v1`);
  });

  // 3. Graceful shutdown
  const shutdown = (signal) => {
    logger.info(`⚠️  ${signal} recebido — encerrando servidor graciosamente...`);
    server.close(() => {
      logger.info('✅ Servidor encerrado com sucesso');
      process.exit(0);
    });
    setTimeout(() => {
      logger.error('❌ Forçando encerramento após timeout');
      process.exit(1);
    }, 10000);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  process.on('unhandledRejection', (reason, promise) => {
    logger.error('Unhandled Rejection:', { reason, promise });
  });

  process.on('uncaughtException', (error) => {
    logger.error('Uncaught Exception:', error);
    process.exit(1);
  });
};

startServer();
