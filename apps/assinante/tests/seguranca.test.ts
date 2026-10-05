import { test } from 'node:test';
import assert from 'node:assert/strict';
import { caminhoInterno } from '../src/lib/seguranca.ts';
import { ehFrequencia } from '../src/lib/planos.ts';

test('caminhoInterno aceita caminhos internos legítimos', () => {
  assert.equal(caminhoInterno('/'), '/');
  assert.equal(caminhoInterno('/dados'), '/dados');
  assert.equal(caminhoInterno('/assinar?plano=semanal'), '/assinar?plano=semanal');
  assert.equal(caminhoInterno('/assinar?plano=semanal&x=%2F%2Fevil.com'), '/assinar?plano=semanal&x=%2F%2Fevil.com');
});

test('caminhoInterno recusa tudo que sai do site (open redirect)', () => {
  const ataques = [
    'https://evil.com',
    'http://evil.com/x',
    '//evil.com',
    '///evil.com',
    '/\\evil.com', // o navegador trata a barra invertida como barra
    '\\\\evil.com',
    '/\t/evil.com',
    '/\n/evil.com',
    '/\r/evil.com',
    'javascript:alert(1)',
    'evil.com',
    'data:text/html,x',
    '  //evil.com',
  ];
  for (const ataque of ataques) {
    assert.equal(caminhoInterno(ataque), '/', `deveria recusar ${JSON.stringify(ataque)}`);
  }
});

test('caminhoInterno usa o padrão para vazio, nulo e excessivamente longo', () => {
  assert.equal(caminhoInterno(undefined), '/');
  assert.equal(caminhoInterno(null), '/');
  assert.equal(caminhoInterno(''), '/');
  assert.equal(caminhoInterno('/' + 'a'.repeat(400)), '/');
  assert.equal(caminhoInterno('https://evil.com', '/entrar'), '/entrar');
});

test('ehFrequencia só aceita os três planos públicos', () => {
  for (const ok of ['semanal', 'quinzenal', 'mensal']) assert.equal(ehFrequencia(ok), true);
  for (const ruim of ['', 'diario', '1', 16400, null, undefined, 'SEMANAL', 'semanal ']) {
    assert.equal(ehFrequencia(ruim), false);
  }
});
