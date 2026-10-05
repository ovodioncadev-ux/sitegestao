/**
 * Formatação para a tela. As consultas devolvem datas como texto (AAAA-MM-DD,
 * via `::text`) — nunca como Date do JavaScript, que aplicaria o fuso da
 * máquina e poderia mostrar o dia anterior.
 */

// O número mora em um lugar só: packages/config/src/whatsapp.mjs.
export { WHATSAPP_URL } from '@ovo/config/whatsapp';

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

/** Máscara (31) 99999-9999 enquanto a pessoa digita. Aceita colar com +55. */
export function mascararTelefone(valor: string): string {
  let d = valor.replace(/\D/g, '');
  if (d.length > 11 && d.startsWith('55')) d = d.slice(2);
  d = d.slice(0, 11);
  if (d.length === 0) return '';
  if (d.length <= 2) return `(${d}`;
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`;
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
}

/** "+5531999999999" (como está no banco) → "(31) 99999-9999". */
export function formatarTelefone(telefone: string | null | undefined): string {
  if (!telefone) return '';
  return mascararTelefone(telefone);
}

export function mascararCep(valor: string): string {
  const d = valor.replace(/\D/g, '').slice(0, 8);
  return d.length > 5 ? `${d.slice(0, 5)}-${d.slice(5)}` : d;
}
