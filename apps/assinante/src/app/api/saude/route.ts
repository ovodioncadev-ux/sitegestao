import { comoAnonimo } from '@ovo/database';

// Nunca em cache: um monitor precisa do estado de agora.
export const dynamic = 'force-dynamic';

/**
 * Verificação de saúde para monitor de disponibilidade e health check de
 * plataforma. Confere só que o app responde e que o banco atende uma consulta
 * trivial. Devolve apenas { ok } (200 ou 503): nada de versão, host, mensagem
 * de erro ou qualquer detalhe que ajude quem está de fora.
 */
export async function GET() {
  try {
    await comoAnonimo((bd) => bd.consultar('select 1'));
    return Response.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (erro) {
    console.error('[saúde] banco indisponível:', erro instanceof Error ? erro.message : erro);
    return Response.json({ ok: false }, { status: 503, headers: { 'Cache-Control': 'no-store' } });
  }
}
