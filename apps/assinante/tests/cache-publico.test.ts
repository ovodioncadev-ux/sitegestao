import { test } from 'node:test';
import assert from 'node:assert/strict';
import { comCachePublico } from '../src/lib/cache-publico.ts';

test('comCachePublico: leituras simultâneas e seguintes dentro do prazo dividem uma só consulta', async () => {
  let consultas = 0;
  const carregar = async () => {
    consultas += 1;
    await new Promise((r) => setTimeout(r, 10));
    return 'planos';
  };
  const [a, b] = await Promise.all([
    comCachePublico('t1', 1000, carregar),
    comCachePublico('t1', 1000, carregar),
  ]);
  assert.equal(a, 'planos');
  assert.equal(b, 'planos');
  assert.equal(await comCachePublico('t1', 1000, carregar), 'planos');
  assert.equal(consultas, 1);
});

test('comCachePublico: depois do prazo consulta de novo', async () => {
  let consultas = 0;
  const carregar = async () => ++consultas;
  assert.equal(await comCachePublico('t2', 5, carregar), 1);
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(await comCachePublico('t2', 5, carregar), 2);
});

test('comCachePublico: erro não fica guardado', async () => {
  let consultas = 0;
  const carregar = async () => {
    consultas += 1;
    if (consultas === 1) throw new Error('banco fora');
    return 'ok';
  };
  await assert.rejects(comCachePublico('t3', 1000, carregar), /banco fora/);
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(await comCachePublico('t3', 1000, carregar), 'ok');
  assert.equal(consultas, 2);
});

test('comCachePublico: chaves diferentes não se misturam', async () => {
  assert.equal(await comCachePublico('t4a', 1000, async () => 'a'), 'a');
  assert.equal(await comCachePublico('t4b', 1000, async () => 'b'), 'b');
});
