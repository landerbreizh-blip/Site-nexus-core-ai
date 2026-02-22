// Reveal elements on scroll
const observerOptions = { threshold: 0.15 };
const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add('animate');
            observer.unobserve(entry.target);
        }
    });
}, observerOptions);

document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('section, .card, .hero-badge, h1, p').forEach(el => {
        el.classList.add('animate');
        observer.observe(el);
    });

    // Simple chart animation simulation
    setInterval(() => {
        const bars = document.querySelectorAll('.bar');
        bars.forEach(bar => {
            const randomHeight = Math.floor(Math.random() * 60) + 30;
            bar.style.height = randomHeight + '%';
        });
    }, 3000);

    // Smooth scroll for navigation
    document.querySelectorAll('nav a').forEach(anchor => {
        anchor.addEventListener('click', function(e) {
            const href = this.getAttribute('href');
            if (href.startsWith('#')) {
                e.preventDefault();
                document.querySelector(href).scrollIntoView({
                    behavior: 'smooth'
                });
            }
        });
    });

    // Form submission handle
    const form = document.querySelector('form');
    if (form) {
        form.addEventListener('submit', (e) => {
            e.preventDefault();
            const btn = form.querySelector('button');
            const originalText = btn.innerText;
            btn.innerText = 'Processando...';
            btn.disabled = true;

            setTimeout(() => {
                alert('Obrigado! O Nexus Core AI já está processando sua solicitação. Entraremos em contato em breve.');
                btn.innerText = originalText;
                btn.disabled = false;
                form.reset();
            }, 1500);
        });
    }
});
