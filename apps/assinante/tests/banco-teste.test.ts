import { test } from 'node:test';
import assert from 'node:assert/strict';
import { identidade, validarBancoDeTeste } from '../../../packages/database/scripts/banco-teste.mjs';

// URLs fictícias, só para exercitar a guarda. Nenhuma é um banco real.
const PRINCIPAL = 'postgresql://dono:x@ep-principal-123.exemplo.neon.tech/neondb?sslmode=require';
const PRINCIPAL_POOLER = 'postgresql://app:y@ep-principal-123-pooler.exemplo.neon.tech/neondb?sslmode=require';
const TESTE = 'postgresql://dono:z@ep-teste-456.exemplo.neon.tech/neondb?sslmode=require';

test('banco de teste: sem DATABASE_TEST_URL falha, e a mensagem explica como configurar', () => {
  const r = validarBancoDeTeste(undefined, [PRINCIPAL]);
  assert.equal(r.ok, false);
  assert.match((r.motivo ?? ''), /DATABASE_TEST_URL não está configurada/);
  assert.match(r.motivo ?? '', /branch/);
  assert.equal(validarBancoDeTeste('', [PRINCIPAL]).ok, false);
});

test('banco de teste: não faz fallback para o banco principal', () => {
  // Mesmo com ADMIN_URL presente, ausência da variável de teste continua sendo erro.
  assert.equal(validarBancoDeTeste(undefined, [PRINCIPAL, PRINCIPAL_POOLER]).ok, false);
});

test('banco de teste: recusa URL igual à do banco principal (inclusive via pooler)', () => {
  assert.equal(validarBancoDeTeste(PRINCIPAL, [PRINCIPAL]).ok, false);
  assert.equal(validarBancoDeTeste(PRINCIPAL_POOLER, [PRINCIPAL]).ok, false);
  assert.equal(validarBancoDeTeste(PRINCIPAL, [null, PRINCIPAL_POOLER]).ok, false);
});

test('banco de teste: aceita um branch diferente', () => {
  assert.equal(validarBancoDeTeste(TESTE, [PRINCIPAL, PRINCIPAL_POOLER]).ok, true);
});

test('banco de teste: recusa texto que não é connection string', () => {
  assert.equal(validarBancoDeTeste('isto nao e url', [PRINCIPAL]).ok, false);
});

test('banco de teste: a mensagem de erro nunca contém a connection string', () => {
  const r = validarBancoDeTeste(PRINCIPAL, [PRINCIPAL]);
  assert.ok(!(r.motivo ?? '').includes('ep-principal'));
  assert.ok(!(r.motivo ?? '').includes(':x@'));
});

test('identidade ignora -pooler e caixa', () => {
  assert.equal(identidade(PRINCIPAL), identidade(PRINCIPAL_POOLER));
});
