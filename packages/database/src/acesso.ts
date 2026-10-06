import 'server-only';

import { Pool, type PoolClient } from 'pg';
import { exigirEnv } from './env';

/**
 * ═══════════════════════════════════════════════════════════════════════
 * A ponte entre "quem está logado no app" e "quem está falando com o banco".
 *
 * No Supabase, o PostgREST fazia isso sozinho. Aqui é nosso, e é a peça
 * que sustenta toda a RLS: cada requisição abre uma transação e, antes de
 * qualquer consulta, veste um papel e declara quem é a pessoa.
 *
 *   set local role app_usuario;
 *   set local app.usuario_id = '<id>';
 *
 * O `set local` morre junto com a transação. Por isso nem com pool de
 * conexão o contexto de um usuário vaza para a requisição seguinte — que
 * é exatamente o erro que esse padrão costuma ter quando é feito com
 * `set` em vez de `set local`.
 *
 * ⚠️  Nenhuma consulta de negócio deve usar `comoAdmin`. Ela existe para
 *     o caminho administrativo, e só depois de exigirDono() ter rodado.
 * ═══════════════════════════════════════════════════════════════════════
 */

/** Os únicos papéis que o servidor pode vestir. Lista fechada, ver abaixo. */
export type PapelDeConexao = 'app_anon' | 'app_usuario' | 'app_pagamentos';

const PAPEIS_PERMITIDOS: readonly PapelDeConexao[] = ['app_anon', 'app_usuario', 'app_pagamentos'];

let poolServidor: Pool | undefined;
let poolAdmin: Pool | undefined;

/**
 * Quanto tempo uma conexão parada fica aberta. Abrir uma nova até o Neon
 * (TLS + autenticação) custa ~1 s; com 10–30 s, quase todo clique depois de
 * ler a tela pagava esse segundo. Conexão parada no pooler do Neon não
 * segura o banco acordado — ele continua podendo suspender.
 */
export const OCIOSIDADE_CONEXAO_MS = 5 * 60_000;

/**
 * O Neon fecha conexões ociosas (e suspende o banco). Quando isso acontece
 * com uma conexão PARADA no pool, o `pg` emite 'error' no pool inteiro; sem um
 * ouvinte, o Node trata como exceção não capturada e derruba o servidor. Com o
 * ouvinte, a conexão morta só é descartada e a próxima requisição abre outra.
 */
export function ouvirErrosDoPool(pool: Pool, nome: string): Pool {
  pool.on('error', (erro) => {
    console.error(`[banco:${nome}] conexão ociosa perdida (será reaberta na próxima requisição):`, erro.message);
  });
  return pool;
}

function conexaoServidor(): Pool {
  poolServidor ??= ouvirErrosDoPool(
    new Pool({
      connectionString: exigirEnv('DATABASE_URL'),
      max: 10,
      idleTimeoutMillis: OCIOSIDADE_CONEXAO_MS,
      keepAlive: true,
    }),
    'servidor',
  );
  return poolServidor;
}

function conexaoAdmin(): Pool {
  poolAdmin ??= ouvirErrosDoPool(
    new Pool({
      connectionString: exigirEnv('DATABASE_ADMIN_URL'),
      max: 4,
      idleTimeoutMillis: OCIOSIDADE_CONEXAO_MS,
      keepAlive: true,
    }),
    'admin',
  );
  return poolAdmin;
}

/** O que chega para quem está dentro da transação. */
export type Executor = {
  consultar<T = Record<string, unknown>>(sql: string, parametros?: unknown[]): Promise<T[]>;
  umaLinha<T = Record<string, unknown>>(sql: string, parametros?: unknown[]): Promise<T | null>;
};

function executor(cliente: PoolClient): Executor {
  return {
    async consultar<T>(sql: string, parametros: unknown[] = []) {
      const { rows } = await cliente.query(sql, parametros);
      return rows as T[];
    },
    async umaLinha<T>(sql: string, parametros: unknown[] = []) {
      const { rows } = await cliente.query(sql, parametros);
      return (rows[0] as T) ?? null;
    },
  };
}

async function emTransacao<T>(
  pool: Pool,
  papel: PapelDeConexao | null,
  usuarioId: string | null,
  trabalho: (bd: Executor) => Promise<T>,
): Promise<T> {
  // O papel NUNCA vem de fora: é uma lista fechada de duas constantes,
  // conferida aqui de novo em tempo de execução. Se algum dia alguém passar
  // outra coisa, quebra alto — antes de abrir conexão.
  if (papel && !PAPEIS_PERMITIDOS.includes(papel)) {
    throw new Error(`papel de conexão não reconhecido: ${papel}`);
  }

  const cliente = await pool.connect();
  try {
    // begin + papel + usuário numa ida só ao banco. Com o Neon a ~170 ms de
    // distância, cada ida conta: eram 3 antes de qualquer consulta, agora é 1.
    //
    // set_config(..., true) é o mesmo que `set local`: morre com a transação.
    // Uma consulta com vários comandos não aceita parâmetro ($1), por isso os
    // valores entram como literal — sempre por escapeLiteral(), nunca crus.
    const contexto = [
      papel ? `set_config('role', ${cliente.escapeLiteral(papel)}, true)` : null,
      `set_config('app.usuario_id', ${cliente.escapeLiteral(usuarioId ?? '')}, true)`,
    ].filter(Boolean);
    await cliente.query(`begin; select ${contexto.join(', ')}`);

    const resultado = await trabalho(executor(cliente));
    await cliente.query('commit');
    return resultado;
  } catch (erro) {
    await cliente.query('rollback').catch(() => {});
    throw erro;
  } finally {
    cliente.release();
  }
}

/** Visitante sem login. Alcança só o que tiver policy para app_anon. */
export function comoAnonimo<T>(trabalho: (bd: Executor) => Promise<T>): Promise<T> {
  return emTransacao(conexaoServidor(), 'app_anon', null, trabalho);
}

/**
 * Webhook de pagamento. Veste o papel app_pagamentos, que só executa
 * confirmar_pagamento_online() e não lê nem escreve mais nada.
 *
 * Só chame depois de CONFERIR o pagamento junto ao provedor: a função do banco
 * confia em quem a chama. O corpo do aviso, sozinho, nunca é prova de pagamento.
 * Fica em um arquivo só (apps/assinante/src/app/api/pagamento/webhook), e
 * scripts/verificar-segredos.sh reprova o uso em qualquer outro lugar.
 */
export function comoPagamentos<T>(trabalho: (bd: Executor) => Promise<T>): Promise<T> {
  return emTransacao(conexaoServidor(), 'app_pagamentos', null, trabalho);
}

/** Pessoa logada. É por aqui que passa quase tudo. */
export function comoUsuario<T>(
  usuarioId: string,
  trabalho: (bd: Executor) => Promise<T>,
): Promise<T> {
  if (!usuarioId) throw new Error('comoUsuario() exige o id de quem está logado');
  return emTransacao(conexaoServidor(), 'app_usuario', usuarioId, trabalho);
}

/**
 * Conexão administrativa: dona das tabelas, IGNORA a RLS.
 *
 * Só depois de exigirDono() ou exigirPapel() ter aprovado, na mesma função.
 * Server Action é um endpoint POST — o middleware pode não cobrir a rota de
 * onde ela foi chamada, e rota pública é justamente onde essa brecha aparece.
 */
export function comoAdmin<T>(
  trabalho: (bd: Executor) => Promise<T>,
  opcoes: { usuarioId?: string } = {},
): Promise<T> {
  if (typeof window !== 'undefined') {
    throw new Error('comoAdmin() foi chamado no navegador.');
  }
  // `usuarioId` NÃO muda o papel de conexão (segue sendo a dona das tabelas):
  // ele só declara QUEM está agindo, e é o que os gatilhos de auditoria gravam
  // em "quem alterou". Sem ele, a alteração fica registrada como do sistema.
  return emTransacao(conexaoAdmin(), null, opcoes.usuarioId ?? null, trabalho);
}

/** Fecha os pools. Para scripts e testes, não para o app. */
export async function encerrarConexoes(): Promise<void> {
  await Promise.all([poolServidor?.end(), poolAdmin?.end()]);
  poolServidor = undefined;
  poolAdmin = undefined;
}
