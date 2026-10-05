'use client';

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
    <section
      id="comparativo"
      style={{ maxWidth: 'var(--largura-conteudo)', margin: '0 auto', padding: `var(--esp-16) var(--esp-6)` }}
    >
      <h2 style={{ textAlign: 'center', fontSize: 'var(--texto-titulo)' }}>Ovo di Onça x supermercado</h2>
      <div className="tabela-rolavel" style={{ marginTop: 'var(--esp-8)' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={{ textAlign: 'left', padding: 'var(--padding-celula)' }}>Critério</th>
              <th style={{ textAlign: 'left', padding: 'var(--padding-celula)' }}>Ovo di Onça</th>
              <th style={{ textAlign: 'left', padding: 'var(--padding-celula)' }}>Supermercado</th>
            </tr>
          </thead>
          <tbody>
            {COMPARISON_ROWS.map((row) => (
              <tr key={row.feature} style={{ borderTop: '1px solid var(--cor-borda)' }}>
                <td style={{ padding: 'var(--padding-celula)' }}>{row.feature}</td>
                <td style={{ padding: 'var(--padding-celula)' }}>{row.ovoDiOnca}</td>
                <td style={{ padding: 'var(--padding-celula)', color: 'var(--cor-texto-suave)' }}>
                  {row.supermarket}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
