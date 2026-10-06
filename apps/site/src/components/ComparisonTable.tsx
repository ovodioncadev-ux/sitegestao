'use client';

import { Secao } from './ui';

const COMPARISON_ROWS = [
  {
    feature: 'Frescor',
    ovoDiOnca: 'Máx. 7 dias entre a colheita e a entrega',
    supermarket: 'Semanas ou meses em estoque',
  },
  {
    feature: 'Criação das galinhas',
    ovoDiOnca: 'Livre, ao ar aberto',
    supermarket: 'Predominantemente em gaiolas',
  },
  {
    feature: 'Entrega',
    ovoDiOnca: 'Direto na sua porta, dia fixo',
    supermarket: 'Você busca',
  },
  {
    feature: 'Frete',
    ovoDiOnca: 'Grátis na área atendida',
    supermarket: '—',
  },
  {
    feature: 'Desconto no 1º mês',
    ovoDiOnca: '10%, cartão ou PIX',
    supermarket: '—',
  },
];

export function ComparisonTable() {
  return (
    <Secao id="comparativo" titulo="Ovo di Onça x supermercado">
      <div className="tabela-rolavel">
        <table className="w-full border-collapse">
          <thead>
            <tr>
              <th className="p-3 text-left">Critério</th>
              <th className="p-3 text-left">Ovo di Onça</th>
              <th className="p-3 text-left">Supermercado</th>
            </tr>
          </thead>
          <tbody>
            {COMPARISON_ROWS.map((row) => (
              <tr key={row.feature} className="border-t border-borda">
                <td className="p-3">{row.feature}</td>
                <td className="p-3">{row.ovoDiOnca}</td>
                <td className="p-3 text-suave">{row.supermarket}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Secao>
  );
}
