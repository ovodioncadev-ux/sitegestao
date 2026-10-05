/**
 * Leitura e normalização do pedido de aviso (corpo JSON de POST /api/interesse).
 * Pura, sem banco: o banco valida de novo em registrar_interesse().
 * Mensagens em pt-BR, genéricas: nada que confirme se um contato já existe.
 */

export const ORIGENS_INTERESSE = ['site', 'assinar'] as const;
export type OrigemInteresse = (typeof ORIGENS_INTERESSE)[number];

export type Interesse = {
  nome: string | null;
  telefone: string | null;
  email: string | null;
  cep: string;
  origem: OrigemInteresse;
};

export type LeituraInteresse =
  | { ok: true; dados: Interesse }
  | { ok: false; erro: string }
  /** Campo-isca preenchido: quem manda é robô. Responde como sucesso e não grava. */
  | { ok: 'isca' };

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function texto(valor: unknown, max: number): string {
  return typeof valor === 'string' ? valor.trim().slice(0, max + 1) : '';
}

export function lerInteresse(corpo: unknown): LeituraInteresse {
  if (typeof corpo !== 'object' || corpo === null) return { ok: false, erro: 'Pedido inválido.' };
  const c = corpo as Record<string, unknown>;

  // Honeypot: o campo existe no formulário, escondido; gente não preenche.
  if (typeof c.website === 'string' && c.website.trim() !== '') return { ok: 'isca' };

  if (c.consentimento !== true) {
    return { ok: false, erro: 'É preciso aceitar o uso do contato para avisar sobre a entrega.' };
  }

  const origem = c.origem;
  if (!(ORIGENS_INTERESSE as readonly unknown[]).includes(origem)) return { ok: false, erro: 'Pedido inválido.' };

  const cep = texto(c.cep, 20).replace(/\D/g, '');
  if (cep.length !== 8) return { ok: false, erro: 'CEP precisa ter 8 dígitos.' };

  let telefone: string | null = texto(c.telefone, 30).replace(/\D/g, '');
  if ((telefone.length === 12 || telefone.length === 13) && telefone.startsWith('55')) telefone = telefone.slice(2);
  if (telefone === '') telefone = null;
  else if (telefone.length < 10 || telefone.length > 11) {
    return { ok: false, erro: 'Telefone precisa ter 10 ou 11 dígitos (com DDD).' };
  }

  const emailBruto = texto(c.email, 254).toLowerCase();
  const email = emailBruto === '' ? null : emailBruto;
  if (email !== null && (email.length > 254 || !EMAIL.test(email))) return { ok: false, erro: 'E-mail inválido.' };

  if (telefone === null && email === null) {
    return { ok: false, erro: 'Informe um telefone ou um e-mail para receber o aviso.' };
  }

  const nomeBruto = texto(c.nome, 120);
  const nome = nomeBruto === '' ? null : nomeBruto;
  if (nome !== null && (nome.length < 2 || nome.length > 120)) {
    return { ok: false, erro: 'Nome precisa ter entre 2 e 120 caracteres.' };
  }

  return { ok: true, dados: { nome, telefone, email, cep, origem: origem as OrigemInteresse } };
}
