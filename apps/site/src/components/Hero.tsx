'use client';

import { urlAssinar } from '@/lib/api';

export function Hero() {
  return (
    <section
      id="inicio"
      style={{
        maxWidth: 'var(--largura-conteudo)',
        margin: '0 auto',
        padding: `var(--esp-24) var(--esp-6)`,
        textAlign: 'center',
      }}
    >
      <h1 style={{ fontSize: 'var(--texto-hero)' }}>Ovos caipiras, da fazenda direto pra sua casa</h1>
      <p style={{ color: 'var(--cor-texto-suave)', marginTop: 'var(--esp-4)', fontSize: 'var(--texto-medio)' }}>
        Máx. 7 dias entre a colheita e a entrega. Frete grátis na área atendida.
      </p>
      <a
        href={urlAssinar('semanal')}
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          textDecoration: 'none',
          marginTop: 'var(--esp-8)',
          background: 'var(--cor-ouro)',
          color: '#fff',
          borderRadius: 'var(--raio-controle)',
          padding: `var(--esp-3) var(--esp-8)`,
          minHeight: 'var(--altura-controle)',
          fontSize: 'var(--texto-medio)',
        }}
      >
        Assinar agora
      </a>
    </section>
  );
}
