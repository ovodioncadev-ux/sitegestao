/**
 * Leitura de corpo JSON com TETO DE TAMANHO, para rotas públicas.
 *
 * `request.json()` e `request.text()` leem o corpo inteiro, de qualquer tamanho, na
 * memória: qualquer anônimo poderia mandar centenas de megabytes. Aqui o corpo é
 * lido em pedaços, contando, e a leitura é ABORTADA ao passar do teto — inclusive
 * quando o cliente não manda `Content-Length` (corpo em pedaços / chunked), caso em
 * que uma checagem só pelo cabeçalho não pega nada.
 */

export type LeituraDeCorpo =
  | { ok: true; valor: unknown }
  /** 413 = passou do teto; 400 = vazio, não é UTF-8 ou não é JSON. */
  | { ok: false; status: 400 | 413 };

export async function lerJsonLimitado(request: Request, maxBytes: number): Promise<LeituraDeCorpo> {
  // Atalho barato: quem declara um corpo grande demais nem começa a ser lido.
  const declarado = Number(request.headers.get('content-length'));
  if (Number.isFinite(declarado) && declarado > maxBytes) return { ok: false, status: 413 };

  if (!request.body) return { ok: false, status: 400 };

  const leitor = request.body.getReader();
  const pedacos: Uint8Array[] = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await leitor.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await leitor.cancel().catch(() => {});
        return { ok: false, status: 413 };
      }
      pedacos.push(value);
    }
  } catch {
    return { ok: false, status: 400 };
  }
  if (total === 0) return { ok: false, status: 400 };

  const inteiro = new Uint8Array(total);
  let posicao = 0;
  for (const pedaco of pedacos) {
    inteiro.set(pedaco, posicao);
    posicao += pedaco.byteLength;
  }

  try {
    return { ok: true, valor: JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(inteiro)) };
  } catch {
    return { ok: false, status: 400 };
  }
}
