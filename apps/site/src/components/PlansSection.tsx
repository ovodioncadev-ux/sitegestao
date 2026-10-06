'use client';

import { usePlanos } from '@/hooks/usePlanos';
import { registrarCliquePlano, urlAssinar } from '@/lib/api';
import { formatarReais, textoDesconto, textoMensal, textoFrescor, textoFrete } from '@/lib/formatar';
import type { Plan } from '@/types';
import { Botao, Cartao, Secao, Selo } from './ui';

export function PlansSection({ inicial }: { inicial?: Plan[] | null }) {
  const { planos, carregando, erro, recarregar } = usePlanos(inicial);

  if (carregando) {
    return (
      <Secao id="planos" titulo="Planos">
        <div role="status" aria-label="Carregando planos" className="grid grid-cols-[repeat(auto-fit,minmax(260px,1fr))] gap-6">
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-72 animate-pulse rounded-card bg-fundo-alt" />
          ))}
        </div>
      </Secao>
    );
  }

  if (erro) {
    return (
      <Secao id="planos" titulo="Planos">
        <div role="alert" className="text-center">
          <p className="text-suave">{erro}</p>
          <Botao variante="contorno" className="mt-4" onClick={recarregar}>
            Tentar de novo
          </Botao>
        </div>
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
            <p className="text-[length:var(--texto-titulo)]">
              {formatarReais(plan.deliveryPriceCents)}
              <span className="text-[length:var(--texto-pequeno)] text-suave"> por entrega</span>
            </p>
            <p className="text-[length:var(--texto-pequeno)] text-suave">{textoMensal(plan)}</p>
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
              onClick={() => registrarCliquePlano(plan.id)}
              variante={plan.highlighted ? 'primario' : 'contorno'}
              className="mt-4 w-full"
            >
              {`Escolher ${plan.name}`}
            </Botao>
          </Cartao>
        ))}
      </div>
    </Secao>
  );
}
