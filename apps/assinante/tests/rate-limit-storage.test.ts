import { test } from 'node:test';
import assert from 'node:assert/strict';
import { criarArmazenamentoDeLimite, type Consulta } from '../../../packages/database/src/auth/rate-limit-storage.ts';

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
