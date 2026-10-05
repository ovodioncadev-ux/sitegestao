'use client';

import { useEffect, useState } from 'react';
import { WHATSAPP_URL } from '@ovo/config/whatsapp';
import { Botao } from './ui';

const LINKS = [
  { href: '#planos', label: 'Planos' },
  { href: '#como-funciona', label: 'Como funciona' },
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

  return (
    <header className="sticky top-0 z-40 border-b border-borda bg-fundo">
      <nav className="mx-auto flex w-full max-w-conteudo flex-wrap items-center justify-between gap-4 px-6 py-3">
        <a href="#inicio" className="font-[family-name:var(--fonte-titulo)] text-[length:var(--texto-medio)]">
          Ovo di Onça
        </a>
        <button
          type="button"
          aria-expanded={aberto}
          aria-controls="menu-principal"
          onClick={() => setAberto((v) => !v)}
          className="min-h-toque rounded-controle border border-borda px-4 md:hidden"
        >
          {aberto ? 'Fechar' : 'Menu'}
        </button>
        <ul
          id="menu-principal"
          className={`${aberto ? 'flex' : 'hidden'} m-0 w-full list-none flex-col gap-4 p-0 md:flex md:w-auto md:flex-row`}
        >
          {LINKS.map((link) => {
            const atual = ativo === link.href.slice(1);
            return (
              <li key={link.href}>
                <a
                  href={link.href}
                  onClick={() => setAberto(false)}
                  aria-current={atual ? 'true' : undefined}
                  className={atual ? 'font-semibold text-ouro-escuro' : 'text-suave'}
                >
                  {link.label}
                </a>
              </li>
            );
          })}
          <li className="md:hidden">
            <a href={WHATSAPP_URL} target="_blank" rel="noreferrer" className="text-ouro-escuro">
              Falar no WhatsApp
            </a>
          </li>
        </ul>
        <div className="hidden md:block">
          <Botao href={WHATSAPP_URL} target="_blank" rel="noreferrer" className="min-h-toque py-2">
            Falar no WhatsApp
          </Botao>
        </div>
      </nav>
    </header>
  );
}
