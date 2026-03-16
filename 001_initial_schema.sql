-- =====================================================
-- NEXUS CORE AI — DATABASE SCHEMA (PostgreSQL)
-- Execute via: psql $DATABASE_URL -f migrations/001_initial_schema.sql
-- Ou cole direto no Supabase SQL Editor
-- =====================================================

-- ─── Extensões ────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- para busca textual eficiente

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
  email       VARCHAR(255) UNIQUE NOT NULL,
  phone       VARCHAR(20),
  cnpj        VARCHAR(18) UNIQUE,
  plan        plan_type DEFAULT 'pro',
  is_active   BOOLEAN DEFAULT true,
  settings    JSONB DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE organizations IS 'Empresas clientes que contrataram a Nexus Core AI';

-- =====================================================
-- TABELA: users (Usuários/Donos das organizações)
-- =====================================================
CREATE TABLE users (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  name            VARCHAR(255) NOT NULL,
  email           VARCHAR(255) UNIQUE NOT NULL,
  password_hash   VARCHAR(255) NOT NULL,
  role            user_role DEFAULT 'viewer',
  is_active       BOOLEAN DEFAULT true,
  last_login      TIMESTAMPTZ,
  refresh_token   TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_org ON users(organization_id);

COMMENT ON TABLE users IS 'Usuários que acessam o dashboard da plataforma';

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
  status          lead_status DEFAULT 'novo',
  source          VARCHAR(100) DEFAULT 'chat_widget',   -- origem: whatsapp, site, direto
  interest        TEXT,                                   -- o que buscou/perguntou
  credit_profile  JSONB DEFAULT '{}',                    -- perfil de crédito extraído
  metadata        JSONB DEFAULT '{}',                    -- dados extras capturados pela IA
  qualified_at    TIMESTAMPTZ,
  closed_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_leads_org ON leads(organization_id);
CREATE INDEX idx_leads_status ON leads(status);
CREATE INDEX idx_leads_created ON leads(created_at DESC);
CREATE INDEX idx_leads_sector ON leads(sector);

COMMENT ON TABLE leads IS 'Leads capturados e qualificados pelo agente de IA';

-- =====================================================
-- TABELA: conversations (Histórico de conversa da IA)
-- =====================================================
CREATE TABLE conversations (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lead_id         UUID REFERENCES leads(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  channel         VARCHAR(50) DEFAULT 'web',  -- web, whatsapp, instagram
  is_active       BOOLEAN DEFAULT true,
  started_at      TIMESTAMPTZ DEFAULT NOW(),
  ended_at        TIMESTAMPTZ,
  summary         TEXT,                        -- resumo gerado pela IA ao final
  metadata        JSONB DEFAULT '{}'
);

CREATE INDEX idx_convs_lead ON conversations(lead_id);
CREATE INDEX idx_convs_org ON conversations(organization_id);

-- =====================================================
-- TABELA: messages (Mensagens individuais de cada conversa)
-- =====================================================
CREATE TABLE messages (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  role            VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content         TEXT NOT NULL,
  tokens_used     INTEGER DEFAULT 0,
  latency_ms      INTEGER,                    -- tempo de resposta da IA em ms
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_messages_conv ON messages(conversation_id);
CREATE INDEX idx_messages_created ON messages(created_at DESC);

COMMENT ON TABLE messages IS 'Mensagens de cada conversa. Permite auditoria e retreinamento.';

-- =====================================================
-- TABELA: analytics_events (Métricas de uso e comportamento)
-- =====================================================
CREATE TABLE analytics_events (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  lead_id         UUID REFERENCES leads(id) ON DELETE SET NULL,
  event_type      VARCHAR(100) NOT NULL,      -- ex: lead_created, lead_qualified, conversation_started
  event_data      JSONB DEFAULT '{}',
  session_id      VARCHAR(255),
  ip_address      INET,
  user_agent      TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_events_org ON analytics_events(organization_id);
CREATE INDEX idx_events_type ON analytics_events(event_type);
CREATE INDEX idx_events_created ON analytics_events(created_at DESC);

COMMENT ON TABLE analytics_events IS 'Eventos para o dashboard de inteligência preditiva';

-- =====================================================
-- TABELA: diagnostic_requests (Formulário da landing page)
-- =====================================================
CREATE TABLE diagnostic_requests (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        VARCHAR(255) NOT NULL,
  email       VARCHAR(255) NOT NULL,
  sector      sector_type NOT NULL,
  status      VARCHAR(50) DEFAULT 'pending',   -- pending, contacted, converted, closed
  notes       TEXT,
  contacted_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_diag_email ON diagnostic_requests(email);
CREATE INDEX idx_diag_status ON diagnostic_requests(status);
CREATE INDEX idx_diag_created ON diagnostic_requests(created_at DESC);

COMMENT ON TABLE diagnostic_requests IS 'Solicitações de diagnóstico gratuito via formulário da landing page';

-- =====================================================
-- TABELA: api_keys (Autenticação de integrações externas)
-- =====================================================
CREATE TABLE api_keys (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name            VARCHAR(100) NOT NULL,
  key_hash        VARCHAR(255) NOT NULL UNIQUE,
  key_prefix      VARCHAR(10) NOT NULL,       -- primeiros 8 chars para identificação
  permissions     JSONB DEFAULT '["read"]',
  last_used_at    TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,
  is_active       BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_apikeys_org ON api_keys(organization_id);
CREATE INDEX idx_apikeys_hash ON api_keys(key_hash);

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
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_organizations_updated BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_leads_updated BEFORE UPDATE ON leads
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Função: estatísticas de leads por organização (usada pelo dashboard)
CREATE OR REPLACE FUNCTION get_lead_stats(org_id UUID, days_back INTEGER DEFAULT 30)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'total_leads',        COUNT(*),
    'new_leads',          COUNT(*) FILTER (WHERE status = 'novo'),
    'qualified_leads',    COUNT(*) FILTER (WHERE status = 'qualificado'),
    'closed_leads',       COUNT(*) FILTER (WHERE status = 'fechado'),
    'qualification_rate', ROUND(
      (COUNT(*) FILTER (WHERE status IN ('qualificado','proposta_enviada','fechado'))::NUMERIC
       / NULLIF(COUNT(*), 0)) * 100, 1
    ),
    'by_sector',          json_agg(DISTINCT sector),
    'period_days',        days_back
  ) INTO result
  FROM leads
  WHERE organization_id = org_id
    AND created_at >= NOW() - (days_back || ' days')::INTERVAL;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- View: dashboard summary por organização
CREATE OR REPLACE VIEW v_dashboard_summary AS
SELECT
  o.id AS organization_id,
  o.name AS organization_name,
  o.sector,
  o.plan,
  COUNT(DISTINCT l.id) AS total_leads,
  COUNT(DISTINCT l.id) FILTER (WHERE l.created_at >= NOW() - INTERVAL '30 days') AS leads_last_30d,
  COUNT(DISTINCT l.id) FILTER (WHERE l.status = 'qualificado') AS qualified_leads,
  COUNT(DISTINCT c.id) AS total_conversations,
  COUNT(DISTINCT dr.id) AS diagnostic_requests
FROM organizations o
LEFT JOIN leads l ON l.organization_id = o.id
LEFT JOIN conversations c ON c.organization_id = o.id
LEFT JOIN diagnostic_requests dr ON dr.email = o.email
WHERE o.is_active = true
GROUP BY o.id, o.name, o.sector, o.plan;

-- =====================================================
-- ROW LEVEL SECURITY (RLS) — Segurança por organização
-- =====================================================
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;

-- Política: cada org só vê seus próprios dados
CREATE POLICY "org_isolation_leads" ON leads
  USING (organization_id = current_setting('app.current_org_id')::UUID);

CREATE POLICY "org_isolation_conversations" ON conversations
  USING (organization_id = current_setting('app.current_org_id')::UUID);

CREATE POLICY "org_isolation_events" ON analytics_events
  USING (organization_id = current_setting('app.current_org_id')::UUID);

-- =====================================================
-- DADOS INICIAIS (Seed)
-- =====================================================
INSERT INTO organizations (id, name, sector, email, phone, plan) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Nexus Core AI (Demo)', 'outro', 'demo@nexuscoreia.com.br', '99703-1366', 'enterprise');

COMMENT ON DATABASE postgres IS 'Nexus Core AI - Production Database v1.0';
