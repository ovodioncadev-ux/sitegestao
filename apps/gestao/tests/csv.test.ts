import { test } from 'node:test';
import assert from 'node:assert/strict';
import { celulaCsv } from '../src/lib/csv.ts';

test('celulaCsv envolve em aspas e dobra as aspas internas', () => {
  assert.equal(celulaCsv('Maria "Mimi" Souza'), '"Maria ""Mimi"" Souza"');
  assert.equal(celulaCsv(null), '""');
});

test('celulaCsv neutraliza fórmulas (injeção de CSV)', () => {
  for (const perigoso of ['=HYPERLINK("http://x")', '+1+1', '-2+3', '@SUM(A1)', '\tcmd', '\rcmd']) {
    assert.ok(celulaCsv(perigoso).startsWith(`"'`), perigoso);
  }
});

test('celulaCsv não mexe em texto comum nem em telefone', () => {
  assert.equal(celulaCsv('31999990000'), '"31999990000"');
  assert.equal(celulaCsv('joao@exemplo.test'), '"joao@exemplo.test"');
});
