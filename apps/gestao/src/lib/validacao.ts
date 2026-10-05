import { ErroNegocio } from './erros';

/**
 * Validação no SERVIDOR, com mensagem pensada para a pessoa. O navegador
 * também valida (required, type=email), mas só para responder rápido — quem
 * decide é este arquivo e, por baixo, as constraints do banco.
 */

const falhar = (mensagem: string): never => {
  throw new ErroNegocio(mensagem);
};

/** Campo de texto do formulário, já aparado. Ausente vira ''. */
export function campo(dados: FormData, nome: string): string {
  return String(dados.get(nome) ?? '').trim();
}

export function textoObrigatorio(valor: string, rotulo: string, max: number): string {
  if (!valor) return falhar(`${rotulo} é obrigatório.`);
  if (valor.length > max) return falhar(`${rotulo} passa de ${max} caracteres.`);
  return valor;
}

export function textoOpcional(valor: string, rotulo: string, max: number): string | null {
  if (!valor) return null;
  if (valor.length > max) return falhar(`${rotulo} passa de ${max} caracteres.`);
  return valor;
}

/** E-mail em minúsculas. O índice único do banco não diferencia caixa, e nós também não. */
export function emailOpcional(valor: string): string | null {
  if (!valor) return null;
  const email = valor.toLowerCase();
  if (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return falhar('E-mail inválido.');
  }
  return email;
}

/** Devolve `+55` + 10 ou 11 dígitos. Aceita com ou sem o 55 na frente. */
export function telefoneOpcional(valor: string): string | null {
  let digitos = valor.replace(/\D/g, '');
  if (digitos === '') return null;
  if ((digitos.length === 12 || digitos.length === 13) && digitos.startsWith('55')) {
    digitos = digitos.slice(2);
  }
  if (digitos.length < 10 || digitos.length > 11) {
    return falhar('Telefone precisa ter 10 ou 11 dígitos (com DDD).');
  }
  return `+55${digitos}`;
}

/** Só os 8 dígitos, sem hífen. */
export function cepOpcional(valor: string): string | null {
  const digitos = valor.replace(/\D/g, '');
  if (digitos === '') return null;
  if (digitos.length !== 8) return falhar('CEP precisa ter 8 dígitos.');
  return digitos;
}

const UFS = new Set(
  'AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO'.split(' '),
);

export function ufOpcional(valor: string): string | null {
  if (!valor) return null;
  const uf = valor.toUpperCase();
  if (!UFS.has(uf)) return falhar('Estado inválido. Use a sigla, como MG.');
  return uf;
}

export function inteiroOpcional(valor: string, rotulo: string, min: number, max: number): number | null {
  if (valor === '') return null;
  return inteiro(valor, rotulo, min, max);
}

export function inteiro(valor: string, rotulo: string, min: number, max: number): number {
  if (!/^-?\d+$/.test(valor)) return falhar(`${rotulo} precisa ser um número inteiro.`);
  const numero = Number(valor);
  if (numero < min || numero > max) return falhar(`${rotulo} precisa estar entre ${min} e ${max}.`);
  return numero;
}

/** "12,5" ou "12.5" → 12.5, sem aceitar lixo. Para percentuais. */
export function decimal(valor: string, rotulo: string, min: number, max: number): number {
  const normal = valor.replace(',', '.');
  if (!/^\d+(\.\d{1,2})?$/.test(normal)) return falhar(`${rotulo} precisa ser um número (ex.: 10 ou 10,5).`);
  const numero = Number(normal);
  if (numero < min || numero > max) return falhar(`${rotulo} precisa estar entre ${min} e ${max}.`);
  return numero;
}

/**
 * "R$ 41,00", "41,00", "41.00", "1.234,56" → centavos inteiros.
 * Dinheiro nunca passa por ponto flutuante neste sistema.
 */
export function reaisParaCentavos(valor: string, rotulo: string, permitirZero = false): number {
  let texto = valor.replace(/R\$|\s/g, '');
  if (texto.includes(',')) texto = texto.replace(/\./g, '').replace(',', '.');
  if (!/^\d+(\.\d{1,2})?$/.test(texto)) return falhar(`${rotulo} inválido. Use o formato 41,00.`);
  const [inteira = '0', fracao = ''] = texto.split('.');
  const centavos = Number(inteira) * 100 + Number(fracao.padEnd(2, '0'));
  if (centavos > 100_000_000) return falhar(`${rotulo} alto demais.`);
  if (centavos === 0 && !permitirZero) return falhar(`${rotulo} precisa ser maior que zero.`);
  return centavos;
}

/** Data no formato AAAA-MM-DD que existe de verdade (nada de 31/02). */
export function dataObrigatoria(valor: string, rotulo: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(valor)) return falhar(`${rotulo} inválida.`);
  const d = new Date(`${valor}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== valor) {
    return falhar(`${rotulo} inválida.`);
  }
  return valor;
}

export function dataOpcional(valor: string, rotulo: string): string | null {
  return valor ? dataObrigatoria(valor, rotulo) : null;
}

/** Id numérico (identity do banco). */
export function idNumerico(valor: string, rotulo: string): number {
  if (!/^\d{1,9}$/.test(valor)) return falhar(`${rotulo} inválido.`);
  return Number(valor);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function uuid(valor: string, rotulo: string): string {
  if (!UUID.test(valor)) return falhar(`${rotulo} inválido.`);
  return valor;
}

export function escolha<T extends string>(valor: string, permitidos: readonly T[], rotulo: string): T {
  if (!(permitidos as readonly string[]).includes(valor)) return falhar(`${rotulo} inválido.`);
  return valor as T;
}

/** Para `ilike`: o que a pessoa digitou vale como texto, não como coringa. */
export function escaparParaBusca(valor: string): string {
  return valor.replace(/[\\%_]/g, (c) => `\\${c}`);
}
