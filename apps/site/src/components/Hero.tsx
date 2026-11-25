'use client';

import { urlWhatsapp } from '@ovo/config/whatsapp';

const BOTAO_BASE = {
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  minHeight: 'var(--altura-controle)',
  padding: `var(--esp-3) var(--esp-6)`,
  borderRadius: 'var(--raio-controle)',
  fontWeight: 600,
  fontSize: 'var(--texto-corpo)',
} as const;

export function Hero() {
  return (
    <section
      id="inicio"
      style={{
        maxWidth: 'var(--largura-conteudo)',
        margin: '0 auto',
        padding: `var(--esp-16) var(--esp-6)`,
      }}
    >
      <h1 style={{ fontSize: 'var(--texto-hero)', color: 'var(--cor-texto)', maxWidth: '20ch' }}>
        Ovo di Onça, o único caipira com a origem no nome.
      </h1>
      <p
        style={{
          color: 'var(--cor-texto-suave)',
          marginTop: 'var(--esp-4)',
          fontSize: 'var(--texto-medio)',
          maxWidth: '56ch',
        }}
      >
        Onça de Pitangui já foi a terra do ouro. Hoje carregamos nossas raízes nos ovos.
      </p>
      <p style={{ marginTop: 'var(--esp-4)', maxWidth: '56ch' }}>
        Máximo de 7 dias entre a colheita e a entrega. Frete incluso na área atendida.
      </p>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 'var(--esp-4)', marginTop: 'var(--esp-8)' }}>
        <a
          href="#planos"
          style={{ ...BOTAO_BASE, background: 'var(--cor-ouro)', color: 'var(--cor-texto)' }}
        >
          Ver planos
        </a>
        <a
          href={urlWhatsapp('Oi! Quero saber mais sobre os planos de ovos.')}
          target="_blank"
          rel="noreferrer"
          style={{ ...BOTAO_BASE, background: 'var(--cor-whatsapp)', color: 'var(--cor-texto-inverso)' }}
        >
          Falar no WhatsApp
        </a>
      </div>
    </section>
  );
}
