import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerInteresse } from '../src/lib/interesse.ts';

const valido = { nome: ' Maria ', telefone: '(31) 99999-0000', cep: '30140-000', origem: 'site', consentimento: true };

test('lerInteresse normaliza telefone, CEP e nome', () => {
  const r = lerInteresse(valido);
  assert.equal(r.ok, true);
  if (r.ok === true) {
    assert.deepEqual(r.dados, { nome: 'Maria', telefone: '31999990000', email: null, cep: '30140000', origem: 'site' });
  }
});

test('lerInteresse aceita só e-mail (minúsculas) e tira o +55 do telefone', () => {
  const r = lerInteresse({ ...valido, telefone: '', email: ' Ana@Exemplo.TEST ' });
  assert.equal(r.ok === true && r.dados.email, 'ana@exemplo.test');
  const t = lerInteresse({ ...valido, telefone: '+55 31 98888-1111' });
  assert.equal(t.ok === true && t.dados.telefone, '31988881111');
});

test('lerInteresse exige consentimento explícito (true, não "true" nem 1)', () => {
  for (const consentimento of [false, undefined, 'true', 1, null]) {
    assert.equal(lerInteresse({ ...valido, consentimento }).ok, false);
  }
});

test('lerInteresse recusa entradas inválidas', () => {
  const ruins: Record<string, unknown>[] = [
    { ...valido, cep: '123' },
    { ...valido, telefone: '123' },
    { ...valido, telefone: '', email: '' },
    { ...valido, email: 'sem-arroba' },
    { ...valido, origem: 'outra' },
    { ...valido, nome: 'A' },
    { ...valido, nome: 'x'.repeat(200) },
  ];
  for (const corpo of ruins) assert.equal(lerInteresse(corpo).ok, false, JSON.stringify(corpo));
  for (const corpo of [null, undefined, 'texto', 42]) assert.equal(lerInteresse(corpo).ok, false);
});

test('lerInteresse trata o campo-isca preenchido como robô (sem erro, sem gravar)', () => {
  assert.equal(lerInteresse({ ...valido, referencia_interna: 'http://spam.example' }).ok, 'isca');
  assert.equal(lerInteresse({ ...valido, referencia_interna: '   ' }).ok, true);
});

test('"website" NÃO é isca: autofill de navegador não pode derrubar um pedido legítimo', () => {
  // Gerenciadores de senha e extensões costumam preencher campos com esse nome sozinhos.
  const r = lerInteresse({ ...valido, website: 'https://meusite.example', url: 'x', phone: 'y' });
  assert.equal(r.ok, true);
});
