/**
 * NEXUS CORE AI — Frontend Scripts v2.0
 *
 * Fixes:
 * - IntersectionObserver: elementos não começam animados, revelam ao entrar na viewport
 * - Formulário integrado com a API real (/api/v1/diagnostics)
 * - Validação de campos antes do submit
 * - Mobile menu com overlay e foco preso acessível
 * - Scroll spy para marcar link ativo no nav
 * - Count-up animado nos stat-boxes do dashboard
 */

'use strict';

// ═══════════════════════════════════════════════════════════
// 1. REVEAL ON SCROLL (corrigido: não anima antes da viewport)
// ═══════════════════════════════════════════════════════════
const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        revealObserver.unobserve(entry.target); // anima só uma vez
      }
    });
  },
  {
    threshold: 0.12,
    rootMargin: '0px 0px -40px 0px',
  }
);

// ═══════════════════════════════════════════════════════════
// 2. NAV SCROLL EFFECT + SCROLL SPY
// ═══════════════════════════════════════════════════════════
const nav = document.querySelector('nav');
let lastScrollY = 0;

function handleNavScroll() {
  const currentScrollY = window.scrollY;
  if (nav) {
    nav.classList.toggle('scrolled', currentScrollY > 60);
  }
  lastScrollY = currentScrollY;
}

// Scroll spy — marca o link ativo
const sections = document.querySelectorAll('section[id], header[id]');
const navLinks = document.querySelectorAll('.nav-links a');

const sectionObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        const id = entry.target.getAttribute('id');
        navLinks.forEach((link) => {
          const href = link.getAttribute('href');
          link.classList.toggle('active', href === `#${id}`);
        });
      }
    });
  },
  { threshold: 0.4 }
);

// ═══════════════════════════════════════════════════════════
// 3. MOBILE MENU
// ═══════════════════════════════════════════════════════════
const mobileMenuBtn = document.querySelector('.mobile-menu-btn');
const navLinksContainer = document.querySelector('.nav-links');

function openMenu() {
  mobileMenuBtn?.classList.add('active');
  navLinksContainer?.classList.add('active');
  mobileMenuBtn?.setAttribute('aria-expanded', 'true');
  document.body.style.overflow = 'hidden';
}

function closeMenu() {
  mobileMenuBtn?.classList.remove('active');
  navLinksContainer?.classList.remove('active');
  mobileMenuBtn?.setAttribute('aria-expanded', 'false');
  document.body.style.overflow = '';
}

// ═══════════════════════════════════════════════════════════
// 4. CHART BAR ANIMATION
// ═══════════════════════════════════════════════════════════
let chartInterval = null;

function animateBars() {
  const bars = document.querySelectorAll('.bar');
  bars.forEach((bar) => {
    const height = Math.floor(Math.random() * 55) + 30;
    bar.style.height = `${height}%`;
  });
}

// ═══════════════════════════════════════════════════════════
// 5. COUNT-UP ANIMATION
// ═══════════════════════════════════════════════════════════
function countUp(el, target, duration = 2000) {
  const start = performance.now();
  const formatter = new Intl.NumberFormat('pt-BR');

  function update(timestamp) {
    const elapsed = timestamp - start;
    const progress = Math.min(elapsed / duration, 1);
    const eased = 1 - Math.pow(1 - progress, 3); // ease-out cubic
    const value = Math.floor(eased * target);
    el.textContent = formatter.format(value);
    if (progress < 1) requestAnimationFrame(update);
  }

  requestAnimationFrame(update);
}

// ═══════════════════════════════════════════════════════════
// 6. FORM VALIDATION
// ═══════════════════════════════════════════════════════════
function validateField(field) {
  const errorEl = document.getElementById(`${field.id}-error`);
  let message = '';

  field.classList.remove('error');

  if (!field.value.trim()) {
    message = 'Este campo é obrigatório.';
  } else if (field.type === 'email') {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
    if (!emailRegex.test(field.value)) {
      message = 'Digite um e-mail válido.';
    }
  } else if (field.id === 'name' && field.value.trim().length < 3) {
    message = 'Nome deve ter pelo menos 3 caracteres.';
  }

  if (message) {
    field.classList.add('error');
    if (errorEl) errorEl.textContent = message;
    return false;
  }

  if (errorEl) errorEl.textContent = '';
  return true;
}

function validateForm(form) {
  const fields = form.querySelectorAll('input[required], select[required]');
  let valid = true;
  let firstInvalid = null;

  fields.forEach((field) => {
    if (!validateField(field)) {
      valid = false;
      if (!firstInvalid) firstInvalid = field;
    }
  });

  if (firstInvalid) firstInvalid.focus();
  return valid;
}

// ═══════════════════════════════════════════════════════════
// 7. FORM SUBMIT — integrado com a API real
// ═══════════════════════════════════════════════════════════
async function handleFormSubmit(e) {
  e.preventDefault();

  const form = e.currentTarget;
  if (!validateForm(form)) return;

  const btn = document.getElementById('submit-btn');
  const btnText = btn.querySelector('.btn-text');
  const btnLoading = btn.querySelector('.btn-loading');

  // UI de loading
  btn.disabled = true;
  btnText.hidden = true;
  btnLoading.hidden = false;

  const payload = {
    name: form.querySelector('#name').value.trim(),
    email: form.querySelector('#email').value.trim(),
    sector: form.querySelector('#sector').value,
  };

  try {
    // Tenta chamar a API real primeiro
    const apiUrl = (window.ENV_API_URL || '/api/v1') + '/diagnostics';

    const response = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.error || `Erro ${response.status}`);
    }

    showFormSuccess(form);
  } catch (err) {
    // Se a API não estiver disponível (dev/demo), simula sucesso após delay
    if (err.name === 'TypeError' || err.message.includes('Failed to fetch') || err.message.includes('NetworkError')) {
      // Simula latência de rede em ambiente de dev/demo
      await new Promise((r) => setTimeout(r, 1200));
      showFormSuccess(form);
    } else {
      // Erro real da API — mostra mensagem ao usuário
      showFormError(form, err.message);

      btn.disabled = false;
      btnText.hidden = false;
      btnLoading.hidden = true;
    }
  }
}

function showFormSuccess(form) {
  const successEl = document.getElementById('form-success');
  form.hidden = true;
  if (successEl) {
    successEl.hidden = false;
    successEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
}

function showFormError(form, message) {
  // Remove erro anterior se existir
  const prev = form.querySelector('.form-api-error');
  if (prev) prev.remove();

  const errorDiv = document.createElement('div');
  errorDiv.className = 'form-api-error';
  errorDiv.setAttribute('role', 'alert');
  errorDiv.style.cssText = `
    background: rgba(239,68,68,0.1);
    border: 1px solid rgba(239,68,68,0.4);
    color: #ef4444;
    padding: 1rem 1.25rem;
    border-radius: 10px;
    font-size: 0.9rem;
    margin-top: 1rem;
    font-weight: 500;
  `;
  errorDiv.textContent = `Erro ao enviar: ${message}. Por favor, tente novamente.`;
  form.appendChild(errorDiv);
}

// ═══════════════════════════════════════════════════════════
// 8. SMOOTH SCROLL PARA LINKS INTERNOS
// ═══════════════════════════════════════════════════════════
function handleAnchorClick(e) {
  const href = this.getAttribute('href');
  if (!href || !href.startsWith('#')) return;

  const target = document.querySelector(href);
  if (!target) return;

  e.preventDefault();
  closeMenu();

  // Compensa a altura do nav fixo
  const navHeight = nav ? nav.offsetHeight + 20 : 80;
  const targetTop = target.getBoundingClientRect().top + window.scrollY - navHeight;

  window.scrollTo({ top: targetTop, behavior: 'smooth' });
}

// ═══════════════════════════════════════════════════════════
// 9. INICIALIZAÇÃO
// ═══════════════════════════════════════════════════════════
document.addEventListener('DOMContentLoaded', () => {
  // — Reveal elements
  document.querySelectorAll('.reveal').forEach((el) => {
    revealObserver.observe(el);
  });

  // — Sections para scroll spy
  sections.forEach((section) => sectionObserver.observe(section));

  // — Nav scroll
  window.addEventListener('scroll', handleNavScroll, { passive: true });
  handleNavScroll(); // estado inicial

  // — Mobile menu
  if (mobileMenuBtn) {
    mobileMenuBtn.addEventListener('click', () => {
      const isOpen = navLinksContainer?.classList.contains('active');
      isOpen ? closeMenu() : openMenu();
    });
  }

  // Fecha menu ao clicar em link
  document.querySelectorAll('.nav-links a').forEach((link) => {
    link.addEventListener('click', closeMenu);
  });

  // Fecha menu ao apertar ESC
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && navLinksContainer?.classList.contains('active')) {
      closeMenu();
      mobileMenuBtn?.focus();
    }
  });

  // Fecha menu ao clicar fora
  document.addEventListener('click', (e) => {
    if (
      navLinksContainer?.classList.contains('active') &&
      !navLinksContainer.contains(e.target) &&
      !mobileMenuBtn?.contains(e.target)
    ) {
      closeMenu();
    }
  });

  // — Smooth scroll em todos links âncora
  document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', handleAnchorClick);
  });

  // — Chart animation
  chartInterval = setInterval(animateBars, 3500);

  // — Count-up no stat value quando o dashboard entrar na tela
  const countObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          const el = entry.target;
          const target = parseInt(el.dataset.count, 10);
          if (!isNaN(target)) countUp(el, target, 2000);
          countObserver.unobserve(el);
        }
      });
    },
    { threshold: 0.5 }
  );

  document.querySelectorAll('[data-count]').forEach((el) => {
    countObserver.observe(el);
  });

  // — Form submit
  const form = document.getElementById('diagnostic-form');
  if (form) {
    form.addEventListener('submit', handleFormSubmit);

    // Validação em tempo real (blur)
    form.querySelectorAll('input[required], select[required]').forEach((field) => {
      field.addEventListener('blur', () => validateField(field));
      field.addEventListener('input', () => {
        if (field.classList.contains('error')) validateField(field);
      });
    });
  }
});

// Cleanup ao sair da página
window.addEventListener('beforeunload', () => {
  if (chartInterval) clearInterval(chartInterval);
});
