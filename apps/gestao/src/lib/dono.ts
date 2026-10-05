import { comoAdmin, type Executor } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { ErroNegocio } from './erros';

/**
 * O único caminho de escrita do painel.
 *
 * Confere que quem chama é o dono (lendo o papel do banco, nunca da
 * requisição) e SÓ ENTÃO abre a conexão administrativa, já declarando quem
 * está agindo para a auditoria. Toda Server Action de escrita passa por aqui —
 * é o mesmo `exigirDono()` + `comoAdmin()` de sempre, em um lugar só, em vez
 * de repetido em cada ação.
 */
export async function comoDono<T>(
  trabalho: (bd: Executor, usuarioId: string) => Promise<T>,
): Promise<T> {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) throw new ErroNegocio(autorizacao.erro);

  const usuarioId = autorizacao.usuario.usuarioId;
  return comoAdmin((bd) => trabalho(bd, usuarioId), { usuarioId });
}
