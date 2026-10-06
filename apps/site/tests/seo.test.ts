import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dadosEstruturados, descricaoDaHome, jsonLdSeguro, urlDoSite } from '../src/lib/seo.ts';

test('urlDoSite: usa a variável, tira a barra final e tem padrão local', () => {
  assert.equal(urlDoSite({ NEXT_PUBLIC_URL_SITE: 'https://ovo.exemplo.com.br/' }), 'https://ovo.exemplo.com.br');
  assert.equal(urlDoSite({}), 'http://localhost:3002');
});

test('jsonLdSeguro: texto do FAQ não consegue fechar o <script>', () => {
  const hostil = '</script><script>alert(1)</script> &  ';
  const saida = jsonLdSeguro({ a: hostil });
  assert.ok(!saida.includes('<') && !saida.includes('>') && !saida.includes('&'));
  assert.ok(!saida.includes(' '));
  assert.deepEqual(JSON.parse(saida), { a: hostil }); // continua JSON idêntico ao ler
});

test('dadosEstruturados: FAQPage só com perguntas visíveis e completas', () => {
  const g = dadosEstruturados({
    urlSite: 'https://x.com',
    telefoneE164: '553125167561',
    faq: [
      { question: 'Como assino?', answer: 'Pelo site.' },
      { question: '  ', answer: 'sem pergunta' },
    ],
  })['@graph'];
  const faq = g.find((n) => n['@type'] === 'FAQPage') as { mainEntity: unknown[] };
  assert.equal(faq.mainEntity.length, 1);
  assert.deepEqual(g.map((n) => n['@type']), ['Organization', 'WebSite', 'FAQPage']);
});

test('dadosEstruturados: sem FAQ não há FAQPage vazio', () => {
  const g = dadosEstruturados({ urlSite: 'https://x.com', telefoneE164: '55', faq: [] })['@graph'];
  assert.ok(!g.some((n) => n['@type'] === 'FAQPage'));
});

test('descricaoDaHome: só afirma o que o banco confirma', () => {
  assert.ok(!/dias|Frete/.test(descricaoDaHome(null)));
  const d = descricaoDaHome({ freshnessMaxDays: 7, freeShipping: true });
  assert.match(d, /No máximo 7 dias/);
  assert.match(d, /Frete incluso/);
});
