import { test } from 'node:test';
import assert from 'node:assert/strict';
import { criarArmazenamentoDeLimite, normalizarChave, type Consulta } from '../../../packages/database/src/auth/rate-limit-storage.ts';

function consultaFixa(linha: { permitido: boolean; retry_apos: number } | null): { consulta: Consulta; chamadas: unknown[][] } {
  const chamadas: unknown[][] = [];
  return {
    chamadas,
    consulta: async (_sql, parametros) => {
      chamadas.push(parametros);
      return { rows: linha ? [linha] : [] };
    },
  };
}

test('consume repassa chave, máximo e janela ao banco, nessa ordem', async () => {
  const { consulta, chamadas } = consultaFixa({ permitido: true, retry_apos: 60 });
  await criarArmazenamentoDeLimite(consulta).consume('203.0.113.1|/sign-in/email', { window: 60, max: 5 });
  assert.deepEqual(chamadas, [['203.0.113.1|/sign-in/email', 5, 60]]);
});

test('consume: dentro do limite → allowed e sem retryAfter', async () => {
  const { consulta } = consultaFixa({ permitido: true, retry_apos: 42 });
  assert.deepEqual(await criarArmazenamentoDeLimite(consulta).consume('k', { window: 60, max: 5 }), {
    allowed: true,
    retryAfter: null,
  });
});

test('consume: estourou → bloqueia e devolve quanto esperar', async () => {
  const { consulta } = consultaFixa({ permitido: false, retry_apos: 37 });
  assert.deepEqual(await criarArmazenamentoDeLimite(consulta).consume('k', { window: 60, max: 5 }), {
    allowed: false,
    retryAfter: 37,
  });
});

test('consume: banco sem linha de resposta libera (não tranca o login por um contador mudo)', async () => {
  const { consulta } = consultaFixa(null);
  assert.deepEqual(await criarArmazenamentoDeLimite(consulta).consume('k', { window: 60, max: 5 }), {
    allowed: true,
    retryAfter: null,
  });
});

test('consume: se o banco falhar, libera e registra (fail-open)', async () => {
  const erros: string[] = [];
  const armazenamento = criarArmazenamentoDeLimite(
    async () => {
      throw new Error('conexão recusada');
    },
    (m) => erros.push(m),
  );
  assert.deepEqual(await armazenamento.consume('k', { window: 60, max: 5 }), { allowed: true, retryAfter: null });
  assert.equal(erros.length, 1);
  assert.match(erros[0] ?? '', /conexão recusada/);
});

test('normalizarChave: chave curta passa intacta; longa vira hash estável e sem colisão', () => {
  assert.equal(normalizarChave('203.0.113.1|/sign-in/email'), '203.0.113.1|/sign-in/email');

  const longaA = `203.0.113.1|/${'a'.repeat(400)}`;
  const longaB = `203.0.113.1|/${'a'.repeat(399)}b`;
  assert.match(normalizarChave(longaA), /^sha256:[0-9a-f]{64}$/);
  assert.equal(normalizarChave(longaA), normalizarChave(longaA)); // mesma chave → mesmo contador
  assert.notEqual(normalizarChave(longaA), normalizarChave(longaB)); // chaves diferentes não colidem
  assert.ok(normalizarChave(longaA).length < 300); // cabe no limite da função do banco
});

test('consume com chave gigante NÃO falha aberto: a chave vai reduzida ao banco', async () => {
  const { consulta, chamadas } = consultaFixa({ permitido: false, retry_apos: 30 });
  const r = await criarArmazenamentoDeLimite(consulta).consume(`ip|/${'z'.repeat(1000)}`, { window: 60, max: 5 });
  assert.equal(r.allowed, false);
  assert.match(String(chamadas[0]?.[0]), /^sha256:/);
});
