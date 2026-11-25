import { test } from 'node:test';
import assert from 'node:assert/strict';
import { prefixarRequisicao } from '../../../packages/database/src/auth/prefixo.ts';

// O Next entrega às rotas o caminho SEM o basePath do app (/api/auth/ok); o
// Better Auth confere o caminho COM ele (/gestao/api/auth/ok). Sem este ajuste
// todo endpoint de auth responde 404 e ninguém consegue entrar.

test('acrescenta o basePath quando o Next o tirou do caminho', () => {
  const r = prefixarRequisicao(new Request('http://localhost:3000/api/auth/ok'), '/gestao');
  assert.equal(new URL(r.url).pathname, '/gestao/api/auth/ok');
});

test('não duplica o basePath quando ele já está no caminho', () => {
  const original = new Request('http://localhost:3000/gestao/api/auth/ok');
  assert.equal(new URL(prefixarRequisicao(original, '/gestao').url).pathname, '/gestao/api/auth/ok');
});

test('sem basePath devolve a mesma requisição', () => {
  const original = new Request('http://localhost:3000/api/auth/ok');
  assert.equal(prefixarRequisicao(original, ''), original);
});

test('não confunde /gestao-x com o prefixo /gestao', () => {
  const r = prefixarRequisicao(new Request('http://localhost:3000/gestao-x/api/auth/ok'), '/gestao');
  assert.equal(new URL(r.url).pathname, '/gestao/gestao-x/api/auth/ok');
});

test('preserva método, cabeçalhos, query e corpo (login é POST com JSON)', async () => {
  const original = new Request('http://localhost:3000/api/auth/sign-in/email?x=1', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: 'http://localhost:3000' },
    body: JSON.stringify({ email: 'a@example.test' }),
  });
  const r = prefixarRequisicao(original, '/gestao');
  assert.equal(r.method, 'POST');
  assert.equal(new URL(r.url).pathname, '/gestao/api/auth/sign-in/email');
  assert.equal(new URL(r.url).search, '?x=1');
  assert.equal(r.headers.get('content-type'), 'application/json');
  assert.equal(r.headers.get('origin'), 'http://localhost:3000');
  assert.deepEqual(await r.json(), { email: 'a@example.test' });
});
