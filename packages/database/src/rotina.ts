import 'server-only';

import { timingSafeEqual } from 'node:crypto';
import { comoAdmin } from './acesso';
import { envOpcional } from './env';

/**
 * Rotina diária disparada por agendador externo (cron), sem pessoa logada.
 *
 * A autorização é o segredo CRON_SECRET, conferido AQUI, no mesmo lugar que
 * abre a conexão administrativa — do mesmo jeito que exigirDono() fica junto
 * de comoAdmin() no painel. Comparação em tempo constante. Sem CRON_SECRET
 * configurado, a rotina por HTTP fica desligada (o dono ainda pode rodá-la
 * pelo botão do painel).
 */
export type ResultadoRotina = {
  data: string;
  reativadas: number;
  cobrancas_geradas: number;
  faturas_atrasadas: number;
  falhas: string[];
};

function segredoConfere(recebido: string | null): boolean {
  const esperado = envOpcional('CRON_SECRET');
  if (!esperado || esperado.length < 32 || !recebido) return false;
  const a = Buffer.from(recebido);
  const b = Buffer.from(esperado);
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function rodarRotinaComSegredo(
  cabecalhoAutorizacao: string | null,
): Promise<ResultadoRotina | null> {
  const recebido = cabecalhoAutorizacao?.startsWith('Bearer ') ? cabecalhoAutorizacao.slice(7) : null;
  if (!segredoConfere(recebido)) return null;

  // usuarioId nulo: a auditoria registra "sistema".
  const linha = await comoAdmin((bd) =>
    bd.umaLinha<{ r: ResultadoRotina }>('select processar_rotina_diaria() as r'),
  );
  return linha?.r ?? null;
}
