# Nexus Core AI — Landing Page & Backend API

Landing page oficial e backend da plataforma **Nexus Core AI**.

## 🚀 O Diferencial

A Nexus Core AI não é apenas um chatbot. É uma plataforma de **Inteligência de Mercado** e **Automação de Vendas** focada em:

- **Imobiliárias:** Atendimento 24/7 e qualificação por perfil de crédito
- **Concessionárias:** Triagem automática de interesse em modelos e consórcios
- **Setor Jurídico:** Triagem de processos e coleta de documentos

---

## 🗂️ Estrutura do Projeto

```
nexus-core-ai/
├── index.html          # Landing page principal
├── termos.html         # Termos de Uso
├── privacidade.html    # Política de Privacidade (LGPD)
├── style.css           # Design system completo
├── script.js           # JavaScript do frontend
├── package.json        # Dependências do backend
├── .env.example        # Template de variáveis de ambiente
├── .gitignore
├── src/
│   ├── app.js          # Express app configuration
│   ├── server.js       # Entry point do servidor
│   ├── config/
│   │   ├── database.js
│   │   └── logger.js
│   └── routes/
│       ├── auth.routes.js
│       ├── lead.routes.js
│       ├── diagnostic.routes.js
│       ├── analytics.routes.js
│       ├── organization.routes.js
│       ├── conversation.routes.js
│       └── webhook.routes.js
└── migrations/
    └── 001_initial_schema.sql
```

---

## 🛠️ Tecnologias Utilizadas

### Frontend
- **HTML5 & CSS3 Premium** — Glassmorphism, animações CSS, design responsivo
- **Vanilla JS (ES2022)** — IntersectionObserver, Fetch API, validação de formulário
- **SEO Otimizado** — Meta tags, Open Graph, Structured Data (JSON-LD)
- **Acessibilidade** — ARIA roles, focus-visible, sr-only, prefers-reduced-motion

### Backend
- **Node.js 18+ & Express 4** — API RESTful
- **PostgreSQL + Supabase** — Banco de dados com RLS por organização
- **JWT + Bcrypt** — Autenticação segura
- **Helmet + CORS + Rate Limiting** — Segurança em camadas
- **Winston** — Logging estruturado

---

## ⚙️ Setup e Instalação

### Pré-requisitos
- Node.js >= 18.0.0
- PostgreSQL 14+ ou conta Supabase
- npm >= 9.0.0

### 1. Clone e instale dependências
```bash
git clone https://github.com/seuuser/nexus-core-ai.git
cd nexus-core-ai
npm install
```

### 2. Configure variáveis de ambiente
```bash
cp .env.example .env
# Edite .env com seus valores reais
```

### 3. Execute as migrations
```bash
# Via psql
psql $DATABASE_URL -f migrations/001_initial_schema.sql

# Ou cole no Supabase SQL Editor
```

### 4. Inicie o servidor
```bash
# Desenvolvimento
npm run dev

# Produção
npm start
```

---

## 🔒 Segurança

- **RLS (Row Level Security)** — Cada organização vê apenas seus dados
  - ⚠️ Define `SET LOCAL app.current_org_id = $1` antes de queries dentro de transações
- **API Keys** — Hash SHA-256 armazenado, nunca a key plain text
- **Webhooks** — Validar assinatura HMAC em `webhook.routes.js`
- **CORS** — Origens autorizadas via `ALLOWED_ORIGINS` no `.env`

---

## 🎨 Identidade Visual

- **Cores:** Midnight Blue `#020617`, Electric Cyan `#0ea5e9`, Aqua `#06b6d4`
- **Tipografia:** Outfit (Títulos, 800w) + Inter (Corpo, 400/600w)
- **Efeitos:** Glassmorphism, glow animations, reveal on scroll

---

## 📡 Endpoints da API

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/health` | Health check |
| POST | `/api/v1/auth/login` | Login de usuário |
| POST | `/api/v1/auth/register` | Registro |
| GET | `/api/v1/leads` | Listar leads da org |
| POST | `/api/v1/leads` | Criar lead |
| POST | `/api/v1/diagnostics` | Solicitação de diagnóstico |
| GET | `/api/v1/analytics` | Métricas da organização |
| GET | `/api/v1/conversations` | Histórico de conversas |

---

## 🌐 Domínio
`nexuscoreia.com.br`

---

## 📄 Licença
© 2026 Nexus Core AI. Todos os direitos reservados.
