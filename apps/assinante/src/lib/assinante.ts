import 'server-only';

import { redirect } from 'next/navigation';
import { comoUsuario, type Executor } from '@ovo/database';
import { usuarioAtual } from '@ovo/database/papel';
import { ErroNegocio } from './erros';

/**
 * O único caminho de acesso a dados do app do assinante.
 *
 * Tudo passa por `comoUsuario`: a conexão veste o papel `app_usuario` e a RLS
 * do Postgres decide o que aparece. Este app NUNCA usa a conexão
 * administrativa — não há nada aqui que precise ignorar a RLS, e é isso que
 * impede que um erro de código vire vazamento de dado de outro cliente.
 *
 * O identificador do cliente nunca vem da requisição: é sempre derivado da
 * sessão (`usuarioAtual`) e conferido de novo no banco.
 */

export type Cliente = {
  id: string;
  nome: string;
  email: string | null;
  telefone: string | null;
  cep: string | null;
  endereco: string | null;
  numero: string | null;
  complemento: string | null;
  bairro: string | null;
  cidade: string | null;
  estado: string | null;
  dentro_area_entrega: boolean;
  codigo_indicacao: string;
};

const COLUNAS_CLIENTE = `id, nome, email, telefone, cep, endereco, numero, complemento,
  bairro, cidade, estado, dentro_area_entrega, codigo_indicacao`;

/** Para páginas: manda para o login se não houver sessão válida. */
export async function exigirSessao(): Promise<{ usuarioId: string }> {
  const usuario = await usuarioAtual();
  if (!usuario) redirect('/entrar');
  return { usuarioId: usuario.usuarioId };
}

/** Para Server Actions: erro legível em vez de redirecionamento. */
export async function comoAssinante<T>(
  trabalho: (bd: Executor, usuarioId: string) => Promise<T>,
): Promise<T> {
  const usuario = await usuarioAtual();
  if (!usuario) throw new ErroNegocio('Sessão expirada. Entre de novo.');
  return comoUsuario(usuario.usuarioId, (bd) => trabalho(bd, usuario.usuarioId));
}

/** O registro de cliente ligado à conta, ou null se ainda não houver vínculo. */
export async function buscarCliente(bd: Executor, usuarioId: string): Promise<Cliente | null> {
  return bd.umaLinha<Cliente>(
    `select ${COLUNAS_CLIENTE} from clientes where usuario_id = $1`,
    [usuarioId],
  );
}
