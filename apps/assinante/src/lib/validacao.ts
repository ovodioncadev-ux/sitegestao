import { ErroNegocio } from './erros';

/**
 * Validação no SERVIDOR, com mensagem pensada para a pessoa. O navegador
 * também valida (required, máscara), mas só para responder rápido — quem
 * decide é este arquivo e, por baixo, as funções e constraints do banco.
 */

const falhar = (mensagem: string): never => {
  throw new ErroNegocio(mensagem);
};

/** Campo de texto do formulário, já aparado. Ausente vira ''. */
export function campo(dados: FormData, nome: string): string {
  return String(dados.get(nome) ?? '').trim();
}

export function textoObrigatorio(valor: string, rotulo: string, min: number, max: number): string {
  if (!valor) return falhar(`${rotulo} é obrigatório.`);
  if (valor.length < min) return falhar(`${rotulo} precisa ter pelo menos ${min} caracteres.`);
  if (valor.length > max) return falhar(`${rotulo} passa de ${max} caracteres.`);
  return valor;
}

export function textoOpcional(valor: string, rotulo: string, max: number): string | null {
  if (!valor) return null;
  if (valor.length > max) return falhar(`${rotulo} passa de ${max} caracteres.`);
  return valor;
}

/** Telefone completo (10 ou 11 dígitos com DDD). Aceita o 55 na frente. */
export function telefoneObrigatorio(valor: string): string {
  let digitos = valor.replace(/\D/g, '');
  if ((digitos.length === 12 || digitos.length === 13) && digitos.startsWith('55')) {
    digitos = digitos.slice(2);
  }
  if (digitos.length < 10 || digitos.length > 11) {
    return falhar('Telefone precisa ter 10 ou 11 dígitos (com DDD).');
  }
  return digitos;
}

/** Só os 8 dígitos, sem hífen. */
export function cepObrigatorio(valor: string): string {
  const digitos = valor.replace(/\D/g, '');
  if (digitos.length !== 8) return falhar('CEP precisa ter 8 dígitos.');
  return digitos;
}

const UFS = new Set(
  'AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO'.split(' '),
);

export function ufObrigatoria(valor: string): string {
  const uf = valor.toUpperCase();
  if (!UFS.has(uf)) return falhar('Estado inválido. Use a sigla, como MG.');
  return uf;
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
