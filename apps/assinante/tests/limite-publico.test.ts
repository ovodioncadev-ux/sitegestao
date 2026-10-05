import { test } from 'node:test';
import assert from 'node:assert/strict';
import { acessoBloqueado, ipDaRequisicao } from '../src/lib/limite-publico.ts';

const cab = (valores: Record<string, string>) => ({ get: (nome: string) => valores[nome] ?? null });

test('ipDaRequisicao usa o primeiro IP de x-forwarded-for', () => {
  assert.equal(ipDaRequisicao(cab({ 'x-forwarded-for': '203.0.113.7, 10.0.0.1' })), '203.0.113.7');
});

test('ipDaRequisicao cai em x-real-ip e, sem nada, em "desconhecido"', () => {
  assert.equal(ipDaRequisicao(cab({ 'x-real-ip': '198.51.100.2' })), '198.51.100.2');
  assert.equal(ipDaRequisicao(cab({})), 'desconhecido');
  assert.equal(ipDaRequisicao(cab({ 'x-forwarded-for': '   ' })), 'desconhecido');
});

function executorFalso(resposta: () => Promise<{ bloqueado: boolean } | null>) {
  const sql: string[] = [];
  return {
    sql,
    bd: {
      consultar: async (texto: string) => {
        sql.push(texto);
        return [];
      },
      umaLinha: async (texto: string) => {
        sql.push(texto);
        return resposta();
      },
    } as never,
  };
}

test('acessoBloqueado devolve o que o banco decidiu e solta o savepoint', async () => {
  const bloqueado = executorFalso(async () => ({ bloqueado: true }));
  assert.equal(await acessoBloqueado(bloqueado.bd, cab({}), 'area'), true);
  assert.ok(bloqueado.sql.includes('release savepoint limite_publico'));

  const livre = executorFalso(async () => ({ bloqueado: false }));
  assert.equal(await acessoBloqueado(livre.bd, cab({}), 'area'), false);
});

test('acessoBloqueado libera (fail-open) e desfaz o savepoint quando o contador falha', async () => {
  const erro = console.error;
  console.error = () => {};
  try {
    const falho = executorFalso(async () => {
      throw new Error('banco fora');
    });
    assert.equal(await acessoBloqueado(falho.bd, cab({}), 'area'), false);
    assert.ok(falho.sql.includes('rollback to savepoint limite_publico'));
  } finally {
    console.error = erro;
  }
});
