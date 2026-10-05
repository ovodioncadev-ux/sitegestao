#!/usr/bin/env node
/**
 * Teste ponta a ponta da D8 (1ª entrega só depois do pagamento) com o PROVEDOR SIMULADO:
 *   site → plano → conta → endereço → confirmar → "falta o pagamento" → Pagar agora →
 *   (simulador avisa o webhook) → fatura paga + 1ª entrega agendada;
 *   e ainda: aviso repetido não duplica, aviso forjado e lixo são recusados.
 *
 * Pré-requisitos — SÓ banco de teste descartável (o script liga a chave D8 e cria dados):
 *   - site (3002) e assinante (3001) no ar com:
 *       PAGAMENTO_PROVEDOR=simulado  PAGAMENTO_SIMULADO_SEGREDO=<o mesmo de E2E_SEGREDO>
 *       URL_PUBLICA_ASSINANTE=http://localhost:3001
 *   - banco de teste migrado, com o papel app_pagamentos concedido ao app_servidor
 *     (pnpm --filter @ovo/database ... criar-papel-servidor) e DATABASE_TEST_URL definida;
 *   - `psql`, o pacote `playwright` (ou E2E_PLAYWRIGHT) e um Chromium (E2E_CHROMIUM).
 *
 *   node scripts/e2e/pagamento.mjs
 */
import { execFileSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const SITE = process.env.E2E_SITE ?? 'http://localhost:3002';
const ASSINANTE = process.env.E2E_ASSINANTE ?? 'http://localhost:3001';
const SEGREDO = process.env.E2E_SEGREDO ?? process.env.PAGAMENTO_SIMULADO_SEGREDO;
const URL_BANCO = process.env.DATABASE_TEST_URL;
const CEP = '30140000';
if (!SEGREDO) throw new Error('Defina E2E_SEGREDO (igual ao PAGAMENTO_SIMULADO_SEGREDO dos apps).');
if (!URL_BANCO) throw new Error('Defina DATABASE_TEST_URL (banco de TESTE descartável).');

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.E2E_PLAYWRIGHT ?? 'playwright');

const sql = (q) => execFileSync('psql', [URL_BANCO, '-At', '-c', q], { encoding: 'utf8' }).trim();
const passo = (t) => console.log(`  ✔ ${t}`);
const assinar = (fatura, transacao, valor, metodo) =>
  createHmac('sha256', SEGREDO).update(`${fatura}|${transacao}|${valor}|${metodo}`).digest('hex');

const email = `e2e-pag-${Date.now()}@exemplo.test`;
let faixaCriada = false;

const navegador = await chromium.launch({ executablePath: process.env.E2E_CHROMIUM, args: ['--no-sandbox'] });
const pagina = await navegador.newPage({ viewport: { width: 1280, height: 900 } });

try {
  if (sql("select count(*) from faixas_cep_atendidas where ativo") === '0') {
    sql("insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000','30190999','E2E pagamento')");
    faixaCriada = true;
  }
  sql('update config_negocio set exigir_pagamento_antes_da_1a_entrega = true, dias_para_pagar_1a_fatura = 7');

  // 1. Assinar pelo site
  await pagina.goto(SITE);
  const escolher = pagina.getByRole('link', { name: 'Escolher Semanal' });
  await escolher.waitFor();
  await Promise.all([pagina.waitForURL(/\/assinar\?plano=semanal/), escolher.click()]);
  await Promise.all([pagina.waitForURL(/\/cadastro/), pagina.getByRole('link', { name: 'Criar conta' }).click()]);
  await pagina.getByLabel('Nome').fill('[TESTE] E2E Pagamento');
  await pagina.getByLabel('E-mail').fill(email);
  await pagina.getByLabel(/Senha/).fill('senha-e2e-segura-12345');
  await Promise.all([pagina.waitForURL(/\/assinar\?plano=semanal/), pagina.getByRole('button', { name: 'Criar conta' }).click()]);
  await pagina.getByLabel('Telefone (com DDD)').fill('31999990000');
  await pagina.getByLabel(/CEP/).fill(CEP);
  await pagina.getByLabel('Rua').fill('Rua de Teste');
  await pagina.getByLabel('Número').fill('100');
  await pagina.getByLabel('Bairro').fill('Centro');
  await pagina.getByLabel('Cidade').fill('Belo Horizonte');
  await pagina.getByLabel(/Estado/).fill('MG');
  await pagina.getByRole('button', { name: 'Continuar' }).click();
  await pagina.getByRole('heading', { name: 'Confirmar assinatura' }).waitFor();
  assert.match(await pagina.locator('main').innerText(), /depois que o pagamento for confirmado/);
  passo('a tela de confirmação avisa que a 1ª entrega só vem depois do pagamento');

  // 2. Confirmar → aguardando pagamento
  await pagina.getByRole('button', { name: 'Confirmar assinatura' }).click();
  await pagina.waitForURL(/\/\?nova=1/);
  await pagina.getByRole('heading', { name: /Falta o pagamento/ }).waitFor();
  assert.match(await pagina.locator('main').innerText(), /Será agendada depois do pagamento/);
  passo('assinatura criada "aguardando o 1º pagamento", sem entrega marcada');

  const clienteId = sql(`select c.id from clientes c join "user" u on u.id = c.usuario_id where u.email = '${email}'`);
  const faturaId = sql(`select id from faturas where cliente_id = '${clienteId}'`);
  assert.equal(sql(`select count(*) from entregas where cliente_id = '${clienteId}'`), '0');
  assert.equal(sql(`select status || '/' || valor_centavos from faturas where id = '${faturaId}'`), 'pendente/14760');
  passo('banco: 0 entregas e 1ª fatura pendente de R$ 147,60 (10% de desconto)');

  // 3. Pagar agora → simulador → webhook
  await Promise.all([pagina.waitForURL(/\/pagamento\/simulado\//), pagina.getByRole('button', { name: 'Pagar agora' }).first().click()]);
  await pagina.getByRole('heading', { name: 'Pagamento simulado' }).waitFor();
  assert.ok(pagina.url().includes(faturaId));
  passo('"Pagar agora" gera o link da PRÓPRIA fatura e leva ao provedor (o simulador é http, então o link não é guardado)');

  await Promise.all([pagina.waitForURL(`${ASSINANTE}/`), pagina.getByRole('button', { name: 'Simular pagamento aprovado' }).click()]);
  await pagina.waitForLoadState('networkidle');
  assert.equal(await pagina.getByRole('heading', { name: /Falta o pagamento/ }).count(), 0);
  assert.equal(sql(`select status from faturas where id = '${faturaId}'`), 'paga');
  assert.equal(sql(`select count(*) from entregas where cliente_id = '${clienteId}'`), '1');
  assert.equal(sql(`select count(*) from assinaturas where cliente_id = '${clienteId}' and aguardando_pagamento_desde is not null`), '0');
  const entrega = sql(`select data_prevista from entregas where cliente_id = '${clienteId}'`);
  assert.equal(sql(`select extract(dow from date '${entrega}')`), '3');
  passo(`o aviso do provedor baixou a fatura e agendou a 1ª entrega (${entrega}, uma quarta)`);

  // 4. Aviso repetido (o provedor reenvia) não duplica nada
  const transacao = sql(`select transacao_id from pagamentos_online where fatura_id = '${faturaId}'`);
  const aviso = (extra = {}) => ({
    fatura: faturaId, transacao, valor: 14760, metodo: 'pix', assinatura: assinar(faturaId, transacao, 14760, 'pix'), ...extra,
  });
  const enviar = (corpo) =>
    pagina.request.post(`${ASSINANTE}/api/pagamento/webhook`, { data: corpo, headers: { 'Content-Type': 'application/json' } });
  let r = await enviar(aviso());
  assert.equal(r.status(), 200);
  assert.equal((await r.json()).resultado, 'ja_processado');
  assert.equal(sql(`select count(*) from pagamentos_online where fatura_id = '${faturaId}'`), '1');
  assert.equal(sql(`select count(*) from entregas where cliente_id = '${clienteId}'`), '1');
  passo('o mesmo aviso de novo: "ja_processado", 1 pagamento e 1 entrega');

  // 5. Aviso forjado e lixo
  r = await enviar({ ...aviso({ transacao: `forjado-${randomUUID()}`, valor: 99999999 }) });
  assert.equal(r.status(), 200);
  assert.equal((await r.json()).resultado, 'nao_pago');
  assert.equal(sql(`select count(*) from pagamentos_online where fatura_id = '${faturaId}'`), '1');
  passo('aviso com assinatura que o provedor não reconhece: "nao_pago", nada gravado');

  for (const lixo of [{}, { fatura: 'x' }, []]) {
    assert.equal((await enviar(lixo)).status(), 400);
  }
  r = await pagina.request.post(`${ASSINANTE}/api/pagamento/webhook`, { data: 'isto não é json', headers: { 'Content-Type': 'application/json' } });
  assert.equal(r.status(), 400);
  passo('corpo que não é aviso (vazio, lixo, não-JSON): 400');

  console.log('\nE2E do pagamento (D8): tudo passou.');
} catch (erro) {
  await pagina.screenshot({ path: 'e2e-falha.png', fullPage: true }).catch(() => {});
  console.error('\n✘ E2E falhou (screenshot em e2e-falha.png):', erro.message);
  process.exitCode = 1;
} finally {
  try {
    sql('update config_negocio set exigir_pagamento_antes_da_1a_entrega = false');
    if (faixaCriada) sql("delete from faixas_cep_atendidas where bairro = 'E2E pagamento'");
  } catch (e) {
    console.error('(não consegui restaurar a chave D8 no banco de teste:', e.message, ')');
  }
  await navegador.close();
}
