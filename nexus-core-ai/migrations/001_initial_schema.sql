-- =====================================================
-- NEXUS CORE AI — DATABASE SCHEMA v1.1 (PostgreSQL)
-- Execute via: psql $DATABASE_URL -f migrations/001_initial_schema.sql
-- Ou cole direto no Supabase SQL Editor
--
-- Fixes v1.1:
--  - Políticas RLS com fallback seguro (não quebra se app.current_org_id não estiver definido)
--  - Índice GIN em metadata/credit_profile para consultas JSONB
--  - Constraint de formato de email via CHECK
--  - messages: índice em role para filtrar por tipo
--  - Comentários expandidos para documentação
-- =====================================================

-- ─── Extensões ────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- busca textual eficiente (ILIKE em grandes tabelas)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- gen_random_uuid() alternativo e funções hash

-- ─── ENUM TYPES ───────────────────────────────────────
CREATE TYPE sector_type AS ENUM (
  'imobiliaria', 'concessionaria', 'consorcio', 'juridico', 'outro'
);

CREATE TYPE lead_status AS ENUM (
  'novo', 'em_contato', 'qualificado', 'proposta_enviada', 'fechado', 'perdido'
);

CREATE TYPE user_role AS ENUM (
  'admin', 'manager', 'viewer'
);

CREATE TYPE plan_type AS ENUM (
  'setup', 'pro', 'enterprise'
);

-- =====================================================
-- TABELA: organizations (Clientes da Nexus Core)
-- =====================================================
CREATE TABLE organizations (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        VARCHAR(255) NOT NULL,
  sector      sector_type NOT NULL,
  email       VARCHAR(255) UNIQUE NOT NULL
                CHECK (email ~* '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'),
  phone       VARCHAR(20),
  cnpj        VARCHAR(18) UNIQUE,
  plan        plan_type DEFAULT 'pro',
  is_active   BOOLEAN DEFAULT true NOT NULL,
  settings    JSONB DEFAULT '{}' NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_organizations_sector   ON organizations(sector);
CREATE INDEX idx_organizations_active   ON organizations(is_active);
CREATE INDEX idx_organizations_plan     ON organizations(plan);

COMMENT ON TABLE organizations IS 'Empresas clientes que contrataram a Nexus Core AI';
COMMENT ON COLUMN organizations.settings IS 'Configurações customizadas por organização (horários, mensagens, integrações)';

-- =====================================================
-- TABELA: users (Usuários/Donos das organizações)
-- =====================================================
CREATE TABLE users (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  name            VARCHAR(255) NOT NULL,
  email           VARCHAR(255) UNIQUE NOT NULL
                    CHECK (email ~* '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'),
  password_hash   VARCHAR(255) NOT NULL,
  role            user_role DEFAULT 'viewer' NOT NULL,
  is_active       BOOLEAN DEFAULT true NOT NULL,
  last_login      TIMESTAMPTZ,
  refresh_token   TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_org   ON users(organization_id);
CREATE INDEX idx_users_role  ON users(role);

COMMENT ON TABLE  users              IS 'Usuários que acessam o dashboard da plataforma';
COMMENT ON COLUMN users.refresh_token IS 'Token de refresh JWT — armazenar hash, não plain text em produção';

-- =====================================================
-- TABELA: leads (Prospects capturados pela IA)
-- =====================================================
CREATE TABLE leads (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name            VARCHAR(255),
  email           VARCHAR(255),
  phone           VARCHAR(20),
  sector          sector_type,
  status          lead_status DEFAULT 'novo' NOT NULL,
  source          VARCHAR(100) DEFAULT 'chat_widget' NOT NULL,  -- whatsapp, site, direto, etc.
  interest        TEXT,                                           -- o que o lead buscou/perguntou
  credit_profile  JSONB DEFAULT '{}' NOT NULL,                  -- perfil de crédito extraído pela IA
  metadata        JSONB DEFAULT '{}' NOT NULL,                  -- dados extras capturados
  qualified_at    TIMESTAMPTZ,
  closed_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_leads_org          ON leads(organization_id);
CREATE INDEX idx_leads_status       ON leads(status);
CREATE INDEX idx_leads_created      ON leads(created_at DESC);
CREATE INDEX idx_leads_sector       ON leads(sector);
CREATE INDEX idx_leads_source       ON leads(source);
-- FIX: índice GIN para queries em JSONB (ex: credit_profile->>'score')
CREATE INDEX idx_leads_credit_gin   ON leads USING GIN (credit_profile);
CREATE INDEX idx_leads_metadata_gin ON leads USING GIN (metadata);

COMMENT ON TABLE  leads                IS 'Leads capturados e qualificados pelo agente de IA';
COMMENT ON COLUMN leads.source         IS 'Canal de origem: chat_widget | whatsapp | instagram | api | manual';
COMMENT ON COLUMN leads.credit_profile IS 'JSON com dados de crédito extraídos pelo agente (renda, score estimado, etc.)';

-- =====================================================
-- TABELA: conversations (Histórico de conversa da IA)
-- =====================================================
CREATE TABLE conversations (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lead_id         UUID REFERENCES leads(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  channel         VARCHAR(50) DEFAULT 'web' NOT NULL,  -- web | whatsapp | instagram | api
  is_active       BOOLEAN DEFAULT true NOT NULL,
  started_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  ended_at        TIMESTAMPTZ,
  summary         TEXT,                                  -- resumo gerado pela IA ao encerrar
  metadata        JSONB DEFAULT '{}' NOT NULL
);

CREATE INDEX idx_convs_lead        ON conversations(lead_id);
CREATE INDEX idx_convs_org         ON conversations(organization_id);
CREATE INDEX idx_convs_channel     ON conversations(channel);
CREATE INDEX idx_convs_active      ON conversations(is_active) WHERE is_active = true;
CREATE INDEX idx_convs_started     ON conversations(started_at DESC);

COMMENT ON TABLE  conversations         IS 'Conversas entre o agente de IA e os leads';
COMMENT ON COLUMN conversations.summary IS 'Resumo automático gerado pela IA ao encerrar a conversa (útil para CRM)';

-- =====================================================
-- TABELA: messages (Mensagens individuais de cada conversa)
-- =====================================================
CREATE TABLE messages (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  role            VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content         TEXT NOT NULL,
  tokens_used     INTEGER DEFAULT 0,
  latency_ms      INTEGER,                     -- latência de resposta da IA em ms
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_messages_conv    ON messages(conversation_id);
CREATE INDEX idx_messages_created ON messages(created_at DESC);
-- FIX: filtrar mensagens por role é comum em auditorias e retreinamento
CREATE INDEX idx_messages_role    ON messages(role);

COMMENT ON TABLE  messages             IS 'Mensagens de cada conversa — permite auditoria e retreinamento de modelos';
COMMENT ON COLUMN messages.latency_ms  IS 'Latência de resposta do LLM em milissegundos — usado no monitoramento de performance';

-- =====================================================
-- TABELA: analytics_events (Métricas de uso e comportamento)
-- =====================================================
CREATE TABLE analytics_events (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  lead_id         UUID REFERENCES leads(id) ON DELETE SET NULL,
  event_type      VARCHAR(100) NOT NULL,       -- lead_created | lead_qualified | conversation_started | ...
  event_data      JSONB DEFAULT '{}' NOT NULL,
  session_id      VARCHAR(255),
  ip_address      INET,
  user_agent      TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_events_org     ON analytics_events(organization_id);
CREATE INDEX idx_events_type    ON analytics_events(event_type);
CREATE INDEX idx_events_created ON analytics_events(created_at DESC);
CREATE INDEX idx_events_lead    ON analytics_events(lead_id) WHERE lead_id IS NOT NULL;
-- FIX: índice GIN para queries no JSONB de event_data
CREATE INDEX idx_events_data_gin ON analytics_events USING GIN (event_data);

COMMENT ON TABLE  analytics_events            IS 'Eventos para o dashboard de inteligência preditiva';
COMMENT ON COLUMN analytics_events.event_type IS 'Tipo do evento: lead_created | lead_qualified | lead_closed | conversation_started | conversation_ended | diagnostic_requested';

-- =====================================================
-- TABELA: diagnostic_requests (Formulário da landing page)
-- =====================================================
CREATE TABLE diagnostic_requests (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name         VARCHAR(255) NOT NULL,
  email        VARCHAR(255) NOT NULL
                 CHECK (email ~* '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'),
  sector       sector_type NOT NULL,
  status       VARCHAR(50) DEFAULT 'pending' NOT NULL
                 CHECK (status IN ('pending', 'contacted', 'converted', 'closed', 'spam')),
  notes        TEXT,
  contacted_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_diag_email   ON diagnostic_requests(email);
CREATE INDEX idx_diag_status  ON diagnostic_requests(status);
CREATE INDEX idx_diag_created ON diagnostic_requests(created_at DESC);
-- Evitar spam: múltiplas solicitações do mesmo email em pouco tempo podem ser detectadas
CREATE INDEX idx_diag_email_created ON diagnostic_requests(email, created_at DESC);

COMMENT ON TABLE  diagnostic_requests        IS 'Solicitações de diagnóstico gratuito via formulário da landing page';
COMMENT ON COLUMN diagnostic_requests.status IS 'pending → contacted → converted | closed | spam';

-- =====================================================
-- TABELA: api_keys (Autenticação de integrações externas)
-- =====================================================
CREATE TABLE api_keys (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name            VARCHAR(100) NOT NULL,
  key_hash        VARCHAR(255) NOT NULL UNIQUE,  -- armazenar HASH da key, nunca plain text
  key_prefix      VARCHAR(10)  NOT NULL,          -- primeiros 8 chars para identificação (ex: "nxc_abc1")
  permissions     JSONB DEFAULT '["read"]' NOT NULL,
  last_used_at    TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,
  is_active       BOOLEAN DEFAULT true NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX idx_apikeys_org    ON api_keys(organization_id);
CREATE INDEX idx_apikeys_hash   ON api_keys(key_hash);
CREATE INDEX idx_apikeys_active ON api_keys(is_active) WHERE is_active = true;

COMMENT ON TABLE  api_keys          IS 'Chaves de API para integrações externas (webhooks, CRM, etc.)';
COMMENT ON COLUMN api_keys.key_hash IS 'Hash SHA-256 da API key — a key real nunca é armazenada';

-- =====================================================
-- FUNÇÕES E TRIGGERS
-- =====================================================

-- Trigger: atualiza updated_at automaticamente
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_organizations_updated
  BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_users_updated
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_leads_updated
  BEFORE UPDATE ON leads
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Função: estatísticas de leads por organização (usada pelo dashboard)
CREATE OR REPLACE FUNCTION get_lead_stats(org_id UUID, days_back INTEGER DEFAULT 30)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  -- Valida que a org existe (evita query vazia sem context)
  IF NOT EXISTS (SELECT 1 FROM organizations WHERE id = org_id AND is_active = true) THEN
    RETURN json_build_object('error', 'Organization not found or inactive');
  END IF;

  SELECT json_build_object(
    'total_leads',          COUNT(*),
    'new_leads',            COUNT(*) FILTER (WHERE status = 'novo'),
    'qualified_leads',      COUNT(*) FILTER (WHERE status = 'qualificado'),
    'closed_leads',         COUNT(*) FILTER (WHERE status = 'fechado'),
    'lost_leads',           COUNT(*) FILTER (WHERE status = 'perdido'),
    'qualification_rate',   ROUND(
      (COUNT(*) FILTER (WHERE status IN ('qualificado','proposta_enviada','fechado'))::NUMERIC
       / NULLIF(COUNT(*), 0)) * 100, 1
    ),
    'conversion_rate',      ROUND(
      (COUNT(*) FILTER (WHERE status = 'fechado')::NUMERIC
       / NULLIF(COUNT(*), 0)) * 100, 1
    ),
    'leads_by_source',      (
      SELECT json_object_agg(source, cnt)
      FROM (
        SELECT source, COUNT(*) AS cnt
        FROM leads
        WHERE organization_id = org_id
          AND created_at >= NOW() - (days_back || ' days')::INTERVAL
        GROUP BY source
      ) s
    ),
    'period_days',          days_back,
    'generated_at',         NOW()
  ) INTO result
  FROM leads
  WHERE organization_id = org_id
    AND created_at >= NOW() - (days_back || ' days')::INTERVAL;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_lead_stats IS 'Retorna estatísticas de leads para o dashboard. Parâmetros: org_id, days_back (default 30).';

-- View: dashboard summary por organização
CREATE OR REPLACE VIEW v_dashboard_summary AS
SELECT
  o.id                  AS organization_id,
  o.name                AS organization_name,
  o.sector,
  o.plan,
  o.is_active,
  COUNT(DISTINCT l.id)  AS total_leads,
  COUNT(DISTINCT l.id) FILTER (
    WHERE l.created_at >= NOW() - INTERVAL '30 days'
  )                     AS leads_last_30d,
  COUNT(DISTINCT l.id) FILTER (
    WHERE l.status = 'qualificado'
  )                     AS qualified_leads,
  COUNT(DISTINCT l.id) FILTER (
    WHERE l.status = 'fechado'
  )                     AS closed_leads,
  ROUND(
    COUNT(DISTINCT l.id) FILTER (WHERE l.status IN ('qualificado','proposta_enviada','fechado'))::NUMERIC
    / NULLIF(COUNT(DISTINCT l.id), 0) * 100, 1
  )                     AS qualification_rate_pct,
  COUNT(DISTINCT c.id)  AS total_conversations,
  COUNT(DISTINCT c.id) FILTER (WHERE c.is_active = true) AS active_conversations,
  COUNT(DISTINCT dr.id) AS diagnostic_requests
FROM organizations o
LEFT JOIN leads l              ON l.organization_id = o.id
LEFT JOIN conversations c      ON c.organization_id = o.id
LEFT JOIN diagnostic_requests dr ON dr.email = o.email
WHERE o.is_active = true
GROUP BY o.id, o.name, o.sector, o.plan, o.is_active;

COMMENT ON VIEW v_dashboard_summary IS 'Resumo consolidado de métricas por organização para o painel administrativo';

-- =====================================================
-- ROW LEVEL SECURITY (RLS) — Isolamento por organização
-- =====================================================
ALTER TABLE leads              ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations      ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages           ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics_events   ENABLE ROW LEVEL SECURITY;

-- FIX CRÍTICO: current_setting com o 2º argumento TRUE retorna NULL
-- em vez de lançar exceção se a variável não estiver definida na sessão.
-- Isso evita queries quebrando fora do contexto da aplicação (ex: migrations, scripts admin).
-- A comparação com NULL resulta em FALSE, bloqueando acesso — comportamento correto e seguro.

CREATE POLICY "org_isolation_leads" ON leads
  USING (
    organization_id = (current_setting('app.current_org_id', true))::UUID
  );

CREATE POLICY "org_isolation_conversations" ON conversations
  USING (
    organization_id = (current_setting('app.current_org_id', true))::UUID
  );

CREATE POLICY "org_isolation_messages" ON messages
  USING (
    conversation_id IN (
      SELECT id FROM conversations
      WHERE organization_id = (current_setting('app.current_org_id', true))::UUID
    )
  );

CREATE POLICY "org_isolation_events" ON analytics_events
  USING (
    organization_id = (current_setting('app.current_org_id', true))::UUID
  );

-- =====================================================
-- DADOS INICIAIS (Seed)
-- =====================================================
INSERT INTO organizations (id, name, sector, email, phone, plan)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Nexus Core AI (Demo)',
  'outro',
  'demo@nexuscoreia.com.br',
  '99703-1366',
  'enterprise'
)
ON CONFLICT (id) DO NOTHING;

-- ─── Observação final ─────────────────────────────────
-- Para usar as políticas RLS no backend Node.js, defina a variável de sessão
-- antes de executar queries:
--   await pool.query("SET LOCAL app.current_org_id = $1", [orgId]);
-- Isso deve ser feito dentro de uma transação (BEGIN...COMMIT).
