'use client';

import { useEffect, useState } from 'react';
import { WHATSAPP_URL } from '@ovo/config/whatsapp';
import { Botao } from './ui';

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
    <header className="sticky top-0 z-40 border-b border-borda bg-fundo">
      <nav className="mx-auto flex w-full max-w-conteudo flex-wrap items-center justify-between gap-4 px-6 py-3">
        <a href="#inicio" className="font-[family-name:var(--fonte-titulo)] text-[length:var(--texto-medio)]">
          Ovo di Onça
        </a>
        <ul className="m-0 flex list-none flex-wrap gap-4 p-0">
          {LINKS.map((link) => {
            const atual = ativo === link.href.slice(1);
            return (
              <li key={link.href}>
                <a
                  href={link.href}
                  aria-current={atual ? 'true' : undefined}
                  className={atual ? 'font-semibold text-ouro-escuro' : 'text-suave'}
                >
                  {link.label}
                </a>
              </li>
            );
          })}
        </ul>
        <Botao href={WHATSAPP_URL} target="_blank" rel="noreferrer" className="min-h-toque py-2">
          Falar no WhatsApp
        </Botao>
      </nav>
    </header>
  );
}
