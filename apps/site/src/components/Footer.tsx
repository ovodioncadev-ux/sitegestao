'use client';

import { WHATSAPP_EXIBICAO, WHATSAPP_URL } from '@ovo/config/whatsapp';

export function Footer() {
  return (
    <footer style={{ borderTop: '1px solid var(--cor-borda)', padding: `var(--esp-8) var(--esp-6)` }}>
      <div
        style={{
          maxWidth: 'var(--largura-conteudo)',
          margin: '0 auto',
          display: 'flex',
          flexWrap: 'wrap',
          justifyContent: 'space-between',
          gap: 'var(--esp-4)',
          color: 'var(--cor-texto-suave)',
        }}
      >
        <span>Ovo di Onça</span>
        <a href={WHATSAPP_URL} target="_blank" rel="noreferrer">
          WhatsApp: {WHATSAPP_EXIBICAO}
        </a>
      </div>
    </footer>
  );
}
