'use client';

import { WHATSAPP_EXIBICAO, WHATSAPP_URL } from '@ovo/config/whatsapp';

export function Footer() {
  return (
    <footer className="border-t border-borda px-6 py-8">
      <div className="mx-auto flex max-w-conteudo flex-wrap justify-between gap-4 text-suave">
        <span>Ovo di Onça</span>
        <a href={WHATSAPP_URL} target="_blank" rel="noreferrer">
          WhatsApp: {WHATSAPP_EXIBICAO}
        </a>
      </div>
    </footer>
  );
}
