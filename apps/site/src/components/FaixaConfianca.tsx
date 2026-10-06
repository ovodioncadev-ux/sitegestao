'use client';

import { useConteudoSite } from '@/hooks/useConteudoSite';
import type { ConteudoSite } from '@/types';
import { Container, Icone, type NomeIcone } from './ui';

/**
 * Só afirma o que o banco confirma: frescor, frete e desconto vêm de
 * /api/site. Sem resposta (ou sem plano ativo), a promessa simplesmente não aparece.
 */
export function FaixaConfianca({ inicial }: { inicial?: ConteudoSite | null }) {
  const { conteudo } = useConteudoSite(inicial);
  if (!conteudo) return null;

  const itens: { icone: NomeIcone; texto: string }[] = [];
  if (conteudo.freshnessMaxDays) {
    itens.push({ icone: 'relogio', texto: `Máx. ${conteudo.freshnessMaxDays} dias da colheita à entrega` });
  }
  if (conteudo.freeShipping) itens.push({ icone: 'caminhao', texto: 'Frete incluso na área atendida' });
  itens.push({ icone: 'calendario', texto: 'Sem fidelidade' });
  if (conteudo.firstMonthDiscountPct) {
    itens.push({ icone: 'selo', texto: `${conteudo.firstMonthDiscountPct}% de desconto no 1º mês` });
  }

  return (
    <section aria-label="Resumo do serviço" className="border-y border-borda bg-superficie-baixa">
      <Container className="py-6">
        <ul className="m-0 grid list-none grid-cols-1 gap-4 p-0 sm:grid-cols-2 lg:grid-cols-4">
          {itens.map((item) => (
            <li key={item.texto} className="flex items-center gap-3 text-[length:var(--texto-pequeno)]">
              <span className="text-ouro-escuro">
                <Icone nome={item.icone} />
              </span>
              {item.texto}
            </li>
          ))}
        </ul>
      </Container>
    </section>
  );
}
