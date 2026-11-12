'use client';

import type { ReactNode } from 'react';
import { usePlanos } from '@/hooks/usePlanos';
import { urlAssinar } from '@/lib/api';
import { formatarReais, textoDesconto, textoFrescor, textoFrete } from '@/lib/formatar';

export function PlansSection() {
  const { planos, carregando, erro, recarregar } = usePlanos();

  // O id fica em todos os estados: o botão "Ver planos" e o menu sempre acham a seção.
  const moldura = (filhos: ReactNode) => (
    <section
      id="planos"
      style={{ maxWidth: 'var(--largura-conteudo)', margin: '0 auto', padding: `var(--esp-16) var(--esp-6)` }}
    >
      <h2 style={{ textAlign: 'center', fontSize: 'var(--texto-titulo)' }}>Planos</h2>
      {filhos}
    </section>
  );

  if (carregando) {
    // Esqueleto com a mesma grade dos cards: evita salto de layout quando os planos chegam.
    return moldura(
      <div
        role="status"
        aria-live="polite"
        aria-label="Carregando planos"
        className="grade-planos"
        style={{ marginTop: 'var(--esp-8)' }}
      >
        {[0, 1, 2].map((i) => (
          <div key={i} className="esqueleto esqueleto-card" aria-hidden="true" />
        ))}
      </div>,
    );
  }

  if (erro) {
    return moldura(
      <div role="alert" style={{ textAlign: 'center', marginTop: 'var(--esp-8)' }}>
        <p>{erro}</p>
        <button type="button" className="botao-contorno" onClick={recarregar} style={{ marginTop: 'var(--esp-4)' }}>
          Tentar de novo
        </button>
      </div>,
    );
  }

  return moldura(
    <div className="grade-planos" style={{ marginTop: 'var(--esp-8)' }}>
      {planos.map((plan) => (
        <article
          key={plan.id}
          style={{
            border: plan.highlighted ? '2px solid var(--cor-ouro)' : '1px solid var(--cor-borda)',
            borderRadius: 'var(--raio-card)',
            padding: 'var(--padding-card)',
            position: 'relative',
          }}
        >
          {plan.badge && (
            <span
              style={{
                position: 'absolute',
                top: 'var(--esp-3)',
                right: 'var(--esp-3)',
                background: 'var(--cor-ouro-app)',
                color: 'var(--cor-texto)',
                borderRadius: 'var(--raio-controle)',
                padding: `var(--esp-1) var(--esp-2)`,
                fontSize: 'var(--texto-rotulo)',
              }}
            >
              {plan.badge}
            </span>
          )}
          <h3>{plan.name}</h3>
          <p style={{ fontSize: 'var(--texto-titulo)' }}>{formatarReais(plan.priceCents)}</p>
          <ul style={{ listStyle: 'none', padding: 0, color: 'var(--cor-texto-suave)' }}>
            <li>{textoFrescor(plan)}</li>
            <li>{textoFrete(plan)}</li>
            <li>{textoDesconto(plan)}</li>
            {plan.features.map((feature) => (
              <li key={feature}>{feature}</li>
            ))}
          </ul>
          <a
            href={urlAssinar(plan.id)}
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              textDecoration: 'none',
              width: '100%',
              marginTop: 'var(--esp-4)',
              background: plan.highlighted ? 'var(--cor-ouro)' : 'transparent',
              color: plan.highlighted ? 'var(--cor-texto)' : 'var(--cor-ouro-escuro)',
              border: plan.highlighted ? 'none' : '1px solid var(--cor-ouro)',
              borderRadius: 'var(--raio-controle)',
              padding: `var(--esp-2) var(--esp-4)`,
              minHeight: 'var(--altura-controle)',
              fontWeight: 600,
            }}
          >
            Escolher {plan.name}
          </a>
        </article>
      ))}
    </div>,
  );
}
