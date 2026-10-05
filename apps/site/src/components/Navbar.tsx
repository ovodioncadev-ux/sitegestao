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

  return (
    <header
      style={{
        position: 'sticky',
        top: 0,
        zIndex: 40,
        background: 'var(--cor-fundo)',
        borderBottom: '1px solid var(--cor-borda)',
      }}
    >
      <nav
        style={{
          maxWidth: 'var(--largura-conteudo)',
          margin: '0 auto',
          padding: `var(--esp-3) var(--esp-6)`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 'var(--esp-4)',
        }}
      >
        <a
          href="#inicio"
          style={{ fontFamily: 'var(--fonte-titulo)', color: 'var(--cor-texto)', fontSize: 'var(--texto-medio)' }}
        >
          Ovo di Onça
        </a>
        <ul style={{ display: 'flex', gap: 'var(--esp-4)', listStyle: 'none', margin: 0, padding: 0 }}>
          {LINKS.map((link) => (
            <li key={link.href}>
              <a
                href={link.href}
                aria-current={ativo === link.href.slice(1) ? 'true' : undefined}
                style={{
                  color: ativo === link.href.slice(1) ? 'var(--cor-ouro-escuro)' : 'var(--cor-texto-suave)',
                  fontWeight: ativo === link.href.slice(1) ? 600 : 400,
                }}
              >
                {link.label}
              </a>
            </li>
          ))}
        </ul>
        <a
          href={WHATSAPP_URL}
          target="_blank"
          rel="noreferrer"
          style={{
            background: 'var(--cor-ouro)',
            color: '#fff',
            borderRadius: 'var(--raio-controle)',
            padding: `var(--esp-2) var(--esp-4)`,
            minHeight: 'var(--alvo-toque)',
            display: 'inline-flex',
            alignItems: 'center',
          }}
        >
          Falar no WhatsApp
        </a>
      </nav>
    </header>
  );
}
