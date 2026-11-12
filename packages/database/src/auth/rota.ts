import 'server-only';

import { toNextJsHandler } from 'better-auth/next-js';
import { auth } from './better-auth';
import { prefixarRequisicao } from './prefixo';

/**
 * GET e POST da rota /api/auth de cada app, já com o caminho corrigido (ver
 * prefixo.ts). O prefixo vem de APP_BASE_PATH, definido no next.config.ts.
 */
export function rotaDoAuth() {
  const prefixo = process.env.APP_BASE_PATH ?? '';
  const handlers = toNextJsHandler(auth);

  return {
    GET: (request: Request) => handlers.GET(prefixarRequisicao(request, prefixo)),
    POST: (request: Request) => handlers.POST(prefixarRequisicao(request, prefixo)),
  };
}
