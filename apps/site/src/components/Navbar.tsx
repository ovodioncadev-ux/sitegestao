'use client';

import { useEffect, useState } from 'react';
import { WHATSAPP_URL } from '@ovo/config/whatsapp';

const LINKS = [
  { href: '#planos', label: 'Planos' },
  { href: '#comparativo', label: 'Comparativo' },
  { href: '#entrega', label: 'Área de entrega' },
  { href: '#faq', label: 'Perguntas frequentes' },
];

export function Navbar() {
  const [ativo, setAtivo] = useState<string>('');
  const [aberto, setAberto] = useState(false);

  // Scroll-spy: os ids observados vêm de LINKS, a mesma lista que monta o menu.
  useEffect(() => {
    const secoes = LINKS.map((l) => document.getElementById(l.href.slice(1))).filter(
      (el): el is HTMLElement => el !== null,
    );
    const observador = new IntersectionObserver(
      (entradas) => {
        const visivel = entradas.find((e) => e.isIntersecting);
        if (visivel) setAtivo(visivel.target.id);
      },
      { rootMargin: '-30% 0px -60% 0px' },
    );
    secoes.forEach((s) => observador.observe(s));
    return () => observador.disconnect();
  }, []);

  // Esc fecha o menu no celular.
  useEffect(() => {
    if (!aberto) return;
    const aoTeclar = (e: KeyboardEvent) => e.key === 'Escape' && setAberto(false);
    window.addEventListener('keydown', aoTeclar);
    return () => window.removeEventListener('keydown', aoTeclar);
  }, [aberto]);

  return (
    <header className="topo">
      <nav className="topo-nav" aria-label="Principal">
        <a href="#inicio" className="topo-marca" onClick={() => setAberto(false)}>
          Ovo di Onça
        </a>
        <button
          type="button"
          className="topo-botao-menu"
          aria-expanded={aberto}
          aria-controls="menu-principal"
          onClick={() => setAberto((v) => !v)}
        >
          {aberto ? 'Fechar' : 'Menu'}
        </button>
        <ul id="menu-principal" className={aberto ? 'topo-links topo-links-abertos' : 'topo-links'}>
          {LINKS.map((link) => {
            const ehAtivo = ativo === link.href.slice(1);
            return (
              <li key={link.href}>
                <a
                  href={link.href}
                  className="topo-link"
                  aria-current={ehAtivo ? 'true' : undefined}
                  data-ativo={ehAtivo ? 'true' : undefined}
                  onClick={() => setAberto(false)}
                >
                  {link.label}
                </a>
              </li>
            );
          })}
          <li className="topo-cta-no-menu">
            <a href={WHATSAPP_URL} target="_blank" rel="noreferrer" className="botao-ouro">
              Falar no WhatsApp
            </a>
          </li>
        </ul>
        <a href={WHATSAPP_URL} target="_blank" rel="noreferrer" className="botao-ouro topo-cta">
          Falar no WhatsApp
        </a>
      </nav>
    </header>
  );
}
