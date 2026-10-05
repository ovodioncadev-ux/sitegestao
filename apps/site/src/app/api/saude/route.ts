// O site não fala com o banco: se responde, está de pé. (O assinante, que o abastece, tem o próprio /api/saude.)
export const dynamic = 'force-dynamic';

export function GET() {
  return Response.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });
}
