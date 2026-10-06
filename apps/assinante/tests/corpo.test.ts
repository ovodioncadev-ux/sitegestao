import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerJsonLimitado } from '../src/lib/corpo.ts';

const URL = 'http://localhost/x';

function post(corpo: BodyInit | null, cabecalhos: Record<string, string> = {}) {
  return new Request(URL, { method: 'POST', body: corpo, headers: cabecalhos });
}

/** Corpo em pedaços, SEM Content-Length: o caso que o teto só pelo cabeçalho não pega. */
function emPedacos(pedacos: number, tamanho: number): Request {
  let enviados = 0;
  const fluxo = new ReadableStream<Uint8Array>({
    pull(controle) {
      if (enviados >= pedacos) return controle.close();
      enviados += 1;
      controle.enqueue(new TextEncoder().encode('a'.repeat(tamanho)));
    },
  });
  // @ts-expect-error `duplex` é exigido pelo Node para corpo em fluxo e não está nos tipos do DOM.
  return new Request(URL, { method: 'POST', body: fluxo, duplex: 'half' });
}

test('corpo dentro do teto: devolve o JSON', async () => {
  const r = await lerJsonLimitado(post('{"etapa":"conta_criada","plano":"semanal"}'), 4096);
  assert.deepEqual(r, { ok: true, valor: { etapa: 'conta_criada', plano: 'semanal' } });
});

test('corpo acima do teto, declarado em Content-Length: 413 sem ler', async () => {
  const r = await lerJsonLimitado(post('{"a":1}', { 'content-length': '999999' }), 100);
  assert.deepEqual(r, { ok: false, status: 413 });
});

test('corpo acima do teto SEM Content-Length (em pedaços): 413 e a leitura é interrompida', async () => {
  const requisicao = emPedacos(1000, 100); // 100 KB em 1000 pedaços
  assert.equal(requisicao.headers.get('content-length'), null);
  assert.deepEqual(await lerJsonLimitado(requisicao, 1000), { ok: false, status: 413 });
});

test('o teto vale pelo que foi realmente enviado, não pelo que o cabeçalho diz', async () => {
  // Cabeçalho mente (diz 10 bytes), corpo real tem 5000.
  const r = await lerJsonLimitado(post('x'.repeat(5000), { 'content-length': '10' }), 1000);
  assert.deepEqual(r, { ok: false, status: 413 });
});

test('JSON inválido, corpo vazio e UTF-8 quebrado: 400', async () => {
  assert.deepEqual(await lerJsonLimitado(post('isto não é json'), 4096), { ok: false, status: 400 });
  assert.deepEqual(await lerJsonLimitado(post(''), 4096), { ok: false, status: 400 });
  assert.deepEqual(await lerJsonLimitado(post(null), 4096), { ok: false, status: 400 });
  assert.deepEqual(await lerJsonLimitado(post(new Uint8Array([0x7b, 0xff, 0xfe, 0x7d])), 4096), { ok: false, status: 400 });
});

test('exatamente no teto passa; um byte a mais não', async () => {
  const json = '{"k":"' + 'a'.repeat(20) + '"}';
  const tamanho = new TextEncoder().encode(json).byteLength;
  assert.equal((await lerJsonLimitado(post(json), tamanho)).ok, true);
  assert.deepEqual(await lerJsonLimitado(post(json), tamanho - 1), { ok: false, status: 413 });
});
