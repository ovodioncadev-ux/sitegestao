/**
 * Formatação para a tela. As consultas devolvem datas como texto (AAAA-MM-DD,
 * via `::text`) — nunca como Date do JavaScript, que aplicaria o fuso da
 * máquina e poderia mostrar o dia anterior.
 */

export function formatarData(iso: string | null | undefined): string {
  if (!iso) return '—';
  const [ano, mes, dia] = iso.slice(0, 10).split('-');
  return `${dia}/${mes}/${ano}`;
}

export function formatarReais(centavos: number | string | null | undefined): string {
  if (centavos === null || centavos === undefined) return '—';
  return (Number(centavos) / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });
}

/** 4100 → "41,00" (para preencher campo de formulário). */
export function centavosParaCampo(centavos: number | string): string {
  return (Number(centavos) / 100).toFixed(2).replace('.', ',');
}

export function formatarTelefone(telefone: string | null | undefined): string {
  if (!telefone) return '—';
  const d = telefone.replace(/\D/g, '').replace(/^55/, '');
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return telefone;
}

export function formatarCep(cep: string | null | undefined): string {
  if (!cep) return '—';
  const d = cep.trim();
  return d.length === 8 ? `${d.slice(0, 5)}-${d.slice(5)}` : d;
}

/** Hoje no fuso de São Paulo, como AAAA-MM-DD — para o padrão dos filtros de data. */
export function hojeEmSaoPaulo(): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}
