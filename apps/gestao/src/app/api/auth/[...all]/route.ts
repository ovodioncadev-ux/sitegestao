import { toNextJsHandler } from 'better-auth/next-js';
import { auth } from '@ovo/database/auth';

const handlers = toNextJsHandler(auth);

export const GET = handlers.GET;

/**
 * O painel do dono não tem cadastro público: contas nascem no app do
 * assinante, e o papel de dono é dado por SQL (definir_papel), nunca por
 * formulário. Sem isto, qualquer um poderia criar conta também por aqui.
 */
export async function POST(request: Request) {
  if (new URL(request.url).pathname.includes('/sign-up')) {
    return Response.json({ message: 'Not found' }, { status: 404 });
  }
  return handlers.POST(request);
}
