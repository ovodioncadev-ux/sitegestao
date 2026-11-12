/**
 * O Next tira o basePath do app (/gestao, /conta) do caminho antes de entregar a
 * requisição à rota: o handler vê `/api/auth/ok`. O Better Auth, configurado com
 * `basePath: /gestao/api/auth`, só reconhece o caminho COM o prefixo. Sem este
 * ajuste, todo endpoint de auth (login, sessão, saída) responde 404.
 *
 * Se o caminho já vier com o prefixo (por exemplo, quando a plataforma não o
 * remove), a requisição segue como está.
 */
export function prefixarRequisicao(request: Request, prefixo: string): Request {
  if (!prefixo) return request;

  const url = new URL(request.url);
  if (url.pathname === prefixo || url.pathname.startsWith(`${prefixo}/`)) return request;
  url.pathname = `${prefixo}${url.pathname}`;

  const temCorpo = request.method !== 'GET' && request.method !== 'HEAD';
  return new Request(url, {
    method: request.method,
    headers: request.headers,
    body: temCorpo ? request.body : undefined,
    signal: request.signal,
    // Obrigatório do Node quando o corpo é um stream.
    ...(temCorpo ? { duplex: 'half' } : {}),
  } as RequestInit);
}
