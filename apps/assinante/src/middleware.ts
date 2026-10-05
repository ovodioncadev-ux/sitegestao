import { NextResponse, type NextRequest } from 'next/server';
import { temCookieDeSessao, redirecionarParaLogin } from '@ovo/database/middleware';

/**
 * ⚠️  CONVENIÊNCIA, NÃO AUTORIZAÇÃO.
 *
 * Ele só olha se existe cookie de sessão, para evitar a tela quebrada de
 * quem não está logado. Ele NÃO valida a sessão contra o banco e NÃO sabe
 * qual é o papel da pessoa — fazer isso aqui, no runtime de borda, custa
 * caro e dá falsa sensação de segurança.
 *
 * Quem protege o dado é a RLS no Postgres, mais o exigirDono()/exigirPapel()
 * dentro de cada Server Action. Nunca troque uma coisa pela outra.
 */

// /assinar é público de propósito: mostra o plano e leva a criar conta. Os passos
// que gravam algo só aparecem com sessão e passam por função do banco.
const ROTAS_PUBLICAS = ['/entrar', '/cadastro', '/assinar', '/recuperar-senha', '/redefinir-senha'];

export function middleware(request: NextRequest) {
  const caminho = request.nextUrl.pathname;

  if (caminho.startsWith('/api/auth')) return NextResponse.next();
  if (caminho.startsWith('/api/plans')) return NextResponse.next();
  if (caminho.startsWith('/api/neighborhoods')) return NextResponse.next();
  if (caminho === '/api/saude') return NextResponse.next();
  if (caminho.startsWith('/api/area')) return NextResponse.next();
  if (caminho.startsWith('/api/site')) return NextResponse.next();
  if (caminho.startsWith('/api/evento')) return NextResponse.next();
  if (caminho.startsWith('/api/interesse')) return NextResponse.next();
  if (caminho.startsWith('/api/pagamento/webhook')) return NextResponse.next();
  if (caminho.startsWith('/pagamento/simulado')) return NextResponse.next();
  if (ROTAS_PUBLICAS.some((rota) => caminho.startsWith(rota))) return NextResponse.next();
  if (!temCookieDeSessao(request)) return redirecionarParaLogin(request);

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
};
