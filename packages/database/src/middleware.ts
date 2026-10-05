import { NextResponse, type NextRequest } from 'next/server';

/**
 * Presença de cookie de sessão, nada além disso.
 *
 * ⚠️  Isto é CONVENIÊNCIA, não autorização. Ele evita a tela quebrada de
 *     quem não está logado; não protege dado nenhum. A defesa real é a RLS
 *     no Postgres mais a checagem dentro de cada Server Action.
 *
 * De propósito o middleware NÃO valida a sessão contra o banco: fazer isso
 * a cada requisição, no runtime de borda, custa caro e dá falsa sensação de
 * segurança. Quem valida de verdade é `usuarioAtual()`, no servidor.
 */

const COOKIE_DE_SESSAO = 'better-auth.session_token';

export function temCookieDeSessao(request: NextRequest): boolean {
  return Boolean(
    request.cookies.get(COOKIE_DE_SESSAO) ??
      request.cookies.get(`__Secure-${COOKIE_DE_SESSAO}`),
  );
}

export function redirecionarParaLogin(request: NextRequest, caminhoLogin = '/entrar') {
  const destino = new URL(caminhoLogin, request.url);
  destino.searchParams.set('voltar', request.nextUrl.pathname);
  return NextResponse.redirect(destino);
}
