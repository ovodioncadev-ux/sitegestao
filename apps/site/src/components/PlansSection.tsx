'use client';

import { usePlanos } from '@/hooks/usePlanos';
import { urlAssinar } from '@/lib/api';
import { formatarReais, textoDesconto, textoFrescor, textoFrete } from '@/lib/formatar';
import { Botao, Cartao, Secao, Selo } from './ui';

export function PlansSection() {
  const { planos, carregando, erro } = usePlanos();

  if (carregando) {
    return (
      <Secao>
        <p>Carregando planos...</p>
      </Secao>
    );
  }

  if (erro) {
    return (
      <Secao>
        <p>Erro ao carregar planos: {erro}</p>
      </Secao>
    );
  }

  return (
    <Secao id="planos" titulo="Planos">
      <div className="grid grid-cols-[repeat(auto-fit,minmax(260px,1fr))] gap-6">
        {planos.map((plan) => (
          <Cartao key={plan.id} destaque={plan.highlighted}>
            {plan.badge && <Selo>{plan.badge}</Selo>}
            <h3>{plan.name}</h3>
            <p className="text-[length:var(--texto-titulo)]">{formatarReais(plan.priceCents)}</p>
            <ul className="m-0 list-none p-0 text-suave">
              <li>{textoFrescor(plan)}</li>
              <li>{textoFrete(plan)}</li>
              <li>{textoDesconto(plan)}</li>
              {plan.features.map((feature) => (
                <li key={feature}>{feature}</li>
              ))}
            </ul>
            <Botao
              href={urlAssinar(plan.id)}
              variante={plan.highlighted ? 'primario' : 'contorno'}
              className="mt-4 w-full"
            >
              Escolher {plan.name}
            </Botao>
          </Cartao>
        ))}
      </div>
    </Secao>
  );
}
