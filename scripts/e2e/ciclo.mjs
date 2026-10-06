#!/usr/bin/env node
/**
 * Teste ponta a ponta das regras D3–D7 (Bloco 10), pelo portal do assinante e pelo painel:
 *   assina → (1ª fatura paga, mês de março/2027 colocado no banco) → pede PAUSA com "pentes depois",
 *   TROCA de plano (redução) e CANCELAMENTO → o dono atende cada um no painel → confere o banco:
 *   pausa com pentes a repor, reativação com 1 + 5 pentes, troca agendada, cancelamento agendado
 *   para o fim do mês pago (aparece no portal) e desfeito.
 *
 * Pré-requisitos (SÓ banco de teste descartável): site (3002), assinante (3001) e gestão (3000) no ar,
 * banco migrado com faixa de CEP ativa cobrindo 30140000, `psql`, DATABASE_TEST_URL, Playwright
 * (E2E_PLAYWRIGHT) e Chromium (E2E_CHROMIUM).
 *
 *   node scripts/e2e/ciclo.mjs
 */
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const SITE = process.env.E2E_SITE ?? 'http://localhost:3002';
const ASSINANTE = process.env.ASSINANTE ?? 'http://localhost:3001';
const GESTAO = process.env.GESTAO ?? 'http://localhost:3000';
const URL_BANCO = process.env.DATABASE_TEST_URL;
const CEP = '30140000';
if (!URL_BANCO) throw new Error('Defina DATABASE_TEST_URL (banco de TESTE descartável).');

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.E2E_PLAYWRIGHT ?? 'playwright');
const sql = (q) => execFileSync('psql', [URL_BANCO, '-At', '-c', q], { encoding: 'utf8' }).trim();
const passo = (t) => console.log(`  ✔ ${t}`);

const ts = Date.now();
const email = `e2e-ciclo-${ts}@exemplo.test`;
const emailDono = `e2e-ciclo-dono-${ts}@exemplo.test`;
const senha = 'senha-e2e-segura-12345';
let faixaCriada = false;

const navegador = await chromium.launch({ executablePath: process.env.E2E_CHROMIUM, args: ['--no-sandbox'] });
const ctxAssinante = await navegador.newContext({ viewport: { width: 1280, height: 900 } });
const ctxDono = await navegador.newContext({ viewport: { width: 1280, height: 900 } });
const portal = await ctxAssinante.newPage();
const painel = await ctxDono.newPage();

async function pedir(rotuloBotao, esperado, preencher) {
  await portal.goto(`${ASSINANTE}/`);
  if (preencher) await preencher();
  await portal.getByRole('button', { name: rotuloBotao }).click();
  await portal.getByText(esperado).first().waitFor();   // o formulário some e vira "aguardando resposta"
}

async function esperar(condicao, tentativas = 40) {
  for (let i = 0; i < tentativas; i++) {
    if (condicao()) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error('condição não ocorreu a tempo');
}

async function atender(textoDaLinha) {
  await painel.goto(`${GESTAO}/assinaturas/${assinaturaId}`);
  const linha = painel.locator('table', { hasText: 'Responder' }).locator('tr', { hasText: textoDaLinha }).first();
  await linha.locator('summary', { hasText: 'Atender' }).click();
  await linha.getByRole('button', { name: 'Atender pedido' }).click();
  await linha.waitFor({ state: 'detached' });   // o pedido sai da lista de pendentes (a mensagem some com a atualização)
}

let assinaturaId;
try {
  if (sql("select count(*) from faixas_cep_atendidas where ativo") === '0') {
    sql("insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000','30190999','E2E ciclo')");
    faixaCriada = true;
  }
  sql('update config_negocio set exigir_pagamento_antes_da_1a_entrega = false');

  // 1. Assina pelo site
  await portal.goto(SITE);
  const escolher = portal.getByRole('link', { name: 'Escolher Semanal' });
  await escolher.waitFor();
  await Promise.all([portal.waitForURL(/\/assinar\?plano=semanal/), escolher.click()]);
  await Promise.all([portal.waitForURL(/\/cadastro/), portal.getByRole('link', { name: 'Criar conta' }).click()]);
  await portal.getByLabel('Nome').fill('[TESTE] E2E Ciclo');
  await portal.getByLabel('E-mail').fill(email);
  await portal.getByLabel(/Senha/).fill(senha);
  await Promise.all([portal.waitForURL(/\/assinar\?plano=semanal/), portal.getByRole('button', { name: 'Criar conta' }).click()]);
  await portal.getByLabel('Telefone (com DDD)').fill('31999990000');
  await portal.getByLabel(/CEP/).fill(CEP);
  await portal.getByLabel('Rua').fill('Rua de Teste');
  await portal.getByLabel('Número').fill('100');
  await portal.getByLabel('Bairro').fill('Centro');
  await portal.getByLabel('Cidade').fill('Belo Horizonte');
  await portal.getByLabel(/Estado/).fill('MG');
  await portal.getByRole('button', { name: 'Continuar' }).click();
  await portal.getByRole('heading', { name: 'Confirmar assinatura' }).waitFor();
  await portal.getByRole('button', { name: 'Confirmar assinatura' }).click();
  await portal.waitForURL(/\/\?nova=1/);
  passo('assinatura criada pelo site');

  assinaturaId = sql(`select a.id from assinaturas a join clientes c on c.id = a.cliente_id join "user" u on u.id = c.usuario_id where u.email = '${email}'`);

  // 2. 1ª fatura paga, com o mês pago colocado em março/2027 (para a conta não depender do dia da execução)
  const faturaId = sql(`select gerar_cobranca('${assinaturaId}')`);
  sql(`select registrar_pagamento('${faturaId}', hoje_sp(), 'pix')`);
  sql(`update faturas set periodo_inicio = '2027-03-01', periodo_fim = '2027-03-31' where id = '${faturaId}'`);
  passo('1ª fatura paga (mês pago: março/2027)');

  // 3. Dono (outra conta, promovida) entra no painel
  const cadastro = await ctxDono.request.post(`${ASSINANTE}/api/auth/sign-up/email`, {
    data: { name: '[TESTE] Dono Ciclo', email: emailDono, password: senha },
    headers: { origin: ASSINANTE },
  });
  assert.ok(cadastro.ok(), `cadastro do dono: HTTP ${cadastro.status()}`);
  sql(`update perfis set papel = 'dono' where id = (select id from "user" where email = '${emailDono}')`);

  // 4. Pedidos do assinante
  await pedir('Pedir pausa', /pedido de pausa está aguardando/, async () => {
    await portal.locator('select[name="preferencia"]').selectOption('pentes');
  });
  await pedir('Pedir troca de plano', /pedido de troca de plano está aguardando/, async () => {
    await portal.locator('select[name="plano_id"]').selectOption({ label: 'Mensal' });
  });
  await pedir('Pedir cancelamento', /pedido de cancelamento está aguardando/);
  assert.equal(sql(`select count(*) from solicitacoes_assinatura where assinatura_id = '${assinaturaId}' and status = 'pendente'`), '3');
  assert.equal(sql(`select preferencia from solicitacoes_assinatura where assinatura_id = '${assinaturaId}' and tipo = 'pausa'`), 'pentes');
  passo('o assinante pediu pausa (pentes depois), troca de plano e cancelamento');

  // 5. Dono atende a pausa: pentes a repor, sem crédito
  await atender('Pausar');
  assert.equal(sql(`select status from assinaturas where id = '${assinaturaId}'`), 'pausada');
  assert.equal(sql(`select destino_credito || '/' || pentes_a_repor || '/' || credito_centavos from pausas_assinatura where assinatura_id = '${assinaturaId}' and status = 'ativa'`), 'pentes/5/0');
  passo('pausa atendida: 5 entregas pagas e não feitas viram 5 pentes a repor (sem crédito)');

  // 6. Reativa: a 1ª entrega do retorno leva 1 + 5 pentes
  await painel.goto(`${GESTAO}/assinaturas/${assinaturaId}`);
  await painel.getByRole('button', { name: 'Reativar assinatura' }).first().click();
  await esperar(() => sql(`select status from assinaturas where id = '${assinaturaId}'`) === 'ativa');
  assert.equal(sql(`select pentes from entregas where assinatura_id = '${assinaturaId}' and status = 'pendente'`), '6');
  passo('reativada: a 1ª entrega do retorno leva 6 pentes (1 + 5 devidos)');

  // 7. Troca (redução) fica agendada para o mês seguinte
  await atender('Trocar de plano');
  assert.match(sql(`select p.nome || '/' || a.plano_proximo_a_partir_de from assinaturas a join planos p on p.id = a.plano_proximo_id where a.id = '${assinaturaId}'`), /^Mensal\/\d{4}-\d{2}-01$/);
  passo('troca para o plano Mensal agendada para o dia 1 do mês seguinte (redução)');

  // 8. Cancelamento vale no fim do mês pago e aparece no portal
  await atender('Cancelar');
  assert.equal(sql(`select cancelamento_agendado_para from assinaturas where id = '${assinaturaId}'`), '2027-03-31');
  assert.equal(sql(`select status from assinaturas where id = '${assinaturaId}'`), 'ativa');
  await portal.goto(`${ASSINANTE}/`);
  await portal.getByRole('heading', { name: 'Cancelamento agendado' }).waitFor();
  passo('cancelamento agendado para 31/03/2027 (fim do mês pago); a assinatura segue ativa e o portal avisa');

  // 9. Dono desfaz
  await painel.goto(`${GESTAO}/assinaturas/${assinaturaId}`);
  await painel.getByText('Cancelar assinatura').first().click();
  await painel.getByRole('button', { name: 'Desfazer cancelamento agendado' }).click();
  await esperar(() => sql(`select cancelamento_agendado_para is null from assinaturas where id = '${assinaturaId}'`) === 't');
  assert.equal(sql(`select coalesce(cancelamento_agendado_para::text, 'nulo') from assinaturas where id = '${assinaturaId}'`), 'nulo');
  passo('o dono desfez o cancelamento agendado');

  // 10. D11: o assinante pede 2 dúzias por entrega; o dono aplica
  await pedir('Pedir dúzias', /pedido de dúzias está aguardando/, async () => {
    await portal.locator('input[name="duzias"]').fill('2');
  });
  await atender('Dúzias');
  assert.equal(sql(`select duzias_padrao from clientes where id = (select cliente_id from assinaturas where id = '${assinaturaId}')`), '2');
  assert.ok(Number(sql(`select count(*) from entregas where assinatura_id = '${assinaturaId}' and status = 'pendente' and duzias = 2`)) >= 1);
  passo('D11: o assinante pediu 2 dúzias por entrega; o dono aplicou e a entrega pendente já leva as dúzias');

  console.log('\nE2E do ciclo (D3–D7 e D11): tudo passou.');
} catch (erro) {
  await portal.screenshot({ path: 'e2e-falha-portal.png', fullPage: true }).catch(() => {});
  await painel.screenshot({ path: 'e2e-falha-painel.png', fullPage: true }).catch(() => {});
  console.error('\n✘ E2E falhou (screenshots e2e-falha-*.png):', erro.message);
  process.exitCode = 1;
} finally {
  try {
    if (faixaCriada) sql("delete from faixas_cep_atendidas where bairro = 'E2E ciclo'");
  } catch (e) {
    console.error('(não consegui limpar a faixa de CEP de teste:', e.message, ')');
  }
  await navegador.close();
}
