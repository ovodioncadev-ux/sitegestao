'use client';

import { usePlanos } from '@/hooks/usePlanos';
import { urlAssinar } from '@/lib/api';
import { formatarReais, textoDesconto, textoFrescor, textoFrete } from '@/lib/formatar';

export function PlansSection() {
  const { planos, carregando, erro } = usePlanos();

  if (carregando) {
    return (
      <section style={{ maxWidth: 'var(--largura-conteudo)', margin: '0 auto', padding: `var(--esp-16) var(--esp-6)` }}>
        <p>Carregando planos...</p>
      </section>
    );
  }

  if (erro) {
    return (
      <section style={{ maxWidth: 'var(--largura-conteudo)', margin: '0 auto', padding: `var(--esp-16) var(--esp-6)` }}>
        <p>Erro ao carregar planos: {erro}</p>
      </section>
    );
  }

  return (
    <section
      id="planos"
      style={{ maxWidth: 'var(--largura-conteudo)', margin: '0 auto', padding: `var(--esp-16) var(--esp-6)` }}
    >
      <h2 style={{ textAlign: 'center', fontSize: 'var(--texto-titulo)' }}>Planos</h2>
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))',
          gap: 'var(--esp-6)',
          marginTop: 'var(--esp-8)',
        }}
      >
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
                color: plan.highlighted ? '#fff' : 'var(--cor-ouro-escuro)',
                border: plan.highlighted ? 'none' : '1px solid var(--cor-ouro)',
                borderRadius: 'var(--raio-controle)',
                padding: `var(--esp-2) var(--esp-4)`,
                minHeight: 'var(--altura-controle)',
              }}
            >
              Escolher {plan.name}
            </a>
          </article>
        ))}
      </div>
    </section>
  );
}
