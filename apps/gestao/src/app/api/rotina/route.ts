import { rodarRotinaComSegredo } from '@ovo/database/rotina';

/**
 * Chamado por agendador externo, uma vez por dia:
 *   POST /api/rotina   Authorization: Bearer <CRON_SECRET>
 * Pode rodar mais de uma vez sem duplicar nada.
 */
export const dynamic = 'force-dynamic';

export async function POST(request: Request) {
  try {
    const resultado = await rodarRotinaComSegredo(request.headers.get('authorization'));
    if (!resultado) return Response.json({ erro: 'Não autorizado' }, { status: 401 });
    return Response.json(resultado);
  } catch (erro) {
    console.error('[rotina diária]', erro);
    return Response.json({ erro: 'Falha na rotina' }, { status: 500 });
  }
}
