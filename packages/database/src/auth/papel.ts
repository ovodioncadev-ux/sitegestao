import 'server-only';

import { headers } from 'next/headers';
import { auth } from './better-auth';
import { comoUsuario } from '../acesso';
import type { PapelUsuario } from '../types';

/**
 * Lei 7 — toda Server Action e todo Route Handler que vai usar a conexão
 * administrativa confere o papel DENTRO dele mesmo, antes de qualquer
 * outra coisa.
 *
 * O papel vem sempre da tabela `perfis`, lida no servidor. Nunca do corpo
 * da requisição, nunca de token editável, nunca de estado do cliente — e
 * repare que a leitura passa por `comoUsuario`, ou seja, ela mesma está
 * sujeita à RLS.
 */

export type Autorizado = {
  usuarioId: string;
  papel: PapelUsuario;
};

export type ResultadoAutorizacao =
  | { ok: true; usuario: Autorizado }
  | { ok: false; erro: string };

/** Quem está logado, com o papel lido do banco. Null se não houver sessão válida. */
export async function usuarioAtual(): Promise<Autorizado | null> {
  const sessao = await auth.api.getSession({ headers: await headers() });
  if (!sessao?.user?.id) return null;

  const usuarioId = sessao.user.id;

  const perfil = await comoUsuario(usuarioId, (bd) =>
    bd.umaLinha<{ papel: PapelUsuario }>('select papel from perfis where id = $1', [usuarioId]),
  );

  if (!perfil) return null;
  return { usuarioId, papel: perfil.papel };
}

/** Exige um dos papéis informados. Mensagem genérica — Lei 9. */
export async function exigirPapel(...papeis: PapelUsuario[]): Promise<ResultadoAutorizacao> {
  const usuario = await usuarioAtual();
  if (!usuario) return { ok: false, erro: 'Sessão expirada. Entre de novo.' };
  if (!papeis.includes(usuario.papel)) {
    return { ok: false, erro: 'Você não tem permissão para realizar esta ação.' };
  }
  return { ok: true, usuario };
}

/** Atalho para o caso mais comum. */
export async function exigirDono(): Promise<ResultadoAutorizacao> {
  return exigirPapel('dono');
}
