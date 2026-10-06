'use client';

import { WHATSAPP_EXIBICAO, WHATSAPP_URL } from '@ovo/config/whatsapp';

export function Footer() {
  return (
    <footer className="border-t border-borda bg-superficie-baixa px-6 py-12">
      <div className="mx-auto grid max-w-conteudo gap-8 text-suave md:grid-cols-3">
        <div>
          <p className="font-[family-name:var(--fonte-titulo)] text-[length:var(--texto-medio)] text-texto">
            Ovo di Onça
          </p>
          <p className="mt-2">Ovos caipiras por assinatura, da fazenda para a sua casa.</p>
        </div>
        <nav aria-label="Rodapé">
          <ul className="m-0 list-none space-y-2 p-0">
            <li><a href="#planos">Planos</a></li>
            <li><a href="#como-funciona">Como funciona</a></li>
            <li><a href="#entrega">Área de entrega</a></li>
            <li><a href="#faq">Perguntas frequentes</a></li>
            <li><a href="/privacidade">Privacidade</a></li>
            <li><a href="/termos">Termos de uso</a></li>
          </ul>
        </nav>
        <div>
          <a href={WHATSAPP_URL} target="_blank" rel="noreferrer">
            WhatsApp: {WHATSAPP_EXIBICAO}
          </a>
        </div>
      </div>
      <p className="mx-auto mt-8 max-w-conteudo text-[length:var(--texto-pequeno)] text-suave">
        © {new Date().getFullYear()} Ovo di Onça. Todos os direitos reservados.
      </p>
    </footer>
  );
}
