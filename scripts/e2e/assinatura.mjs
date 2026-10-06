#!/usr/bin/env node
/**
 * Teste ponta a ponta do fluxo de assinatura:
 *   site → plano → conta → endereço → confirmação → /?nova=1 (+ contagem do funil).
 *
 * Pré-requisitos (ambiente LOCAL ou de teste, nunca o banco principal):
 *   - site (3002) e assinante (3001) no ar, ligados a um banco de teste migrado;
 *   - ao menos uma faixa de CEP ativa que cubra E2E_CEP (padrão 30140000);
 *   - o pacote `playwright` resolvível (ou E2E_PLAYWRIGHT apontando para ele) e um
 *     Chromium (E2E_CHROMIUM = caminho do executável, se não for o padrão do Playwright);
 *   - DATABASE_TEST_URL, só para conferir a contagem do funil (opcional, usa `psql`).
 *
 *   node scripts/e2e/assinatura.mjs
 *
 * Cria uma conta de teste com e-mail único a cada execução (nome "[TESTE] E2E");
 * `pnpm db:limpar-teste` remove os dados [TESTE].
 */
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const SITE = process.env.E2E_SITE ?? 'http://localhost:3002';
const CEP = process.env.E2E_CEP ?? '30140000';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.E2E_PLAYWRIGHT ?? 'playwright');

const email = `e2e-${Date.now()}@exemplo.test`;
const senha = 'senha-e2e-segura-12345';

function contarFunil() {
  const url = process.env.DATABASE_TEST_URL;
  if (!url) return null;
  const saida = execFileSync(
    'psql',
    [url, '-At', '-c', "select etapa || '=' || count(*) from eventos_funil group by etapa order by etapa"],
    { encoding: 'utf8' },
  );
  return Object.fromEntries(
    saida
      .trim()
      .split('\n')
      .filter(Boolean)
      .map((linha) => linha.split('=')),
  );
}

const navegador = await chromium.launch({
  executablePath: process.env.E2E_CHROMIUM,
  args: ['--no-sandbox'],
});
const pagina = await navegador.newPage({ viewport: { width: 1280, height: 900 } });
const passo = (texto) => console.log(`  ✔ ${texto}`);

try {
  const antes = contarFunil();

  // 1. Site → plano semanal
  await pagina.goto(SITE);
  const escolher = pagina.getByRole('link', { name: 'Escolher Semanal' });
  await escolher.waitFor();
  await Promise.all([pagina.waitForURL(/\/assinar\?plano=semanal/), escolher.click()]);
  passo('site leva ao /assinar?plano=semanal');

  // 2. Sem conta: etapa 2 e botão de criar conta
  assert.equal(await pagina.locator('[aria-current="step"]').innerText(), '2\nConta');
  await Promise.all([pagina.waitForURL(/\/cadastro/), pagina.getByRole('link', { name: 'Criar conta' }).click()]);
  passo('cadastro aberto com o indicador de etapas (etapa 2)');

  // 3. Conta
  await pagina.getByLabel('Nome').fill('[TESTE] E2E');
  await pagina.getByLabel('E-mail').fill(email);
  await pagina.getByLabel(/Senha/).fill(senha);
  await Promise.all([
    pagina.waitForURL(/\/assinar\?plano=semanal/),
    pagina.getByRole('button', { name: 'Criar conta' }).click(),
  ]);
  passo('conta criada e retorno ao /assinar');

  // 4. Endereço (etapa 3)
  assert.match(await pagina.locator('[aria-current="step"]').innerText(), /Endereço/);
  await pagina.getByLabel('Telefone (com DDD)').fill('31999990000');
  await pagina.getByLabel(/CEP/).fill(CEP);
  await pagina.getByLabel('Rua').fill('Rua de Teste');
  await pagina.getByLabel('Número').fill('100');
  await pagina.getByLabel('Bairro').fill('Centro');
  await pagina.getByLabel('Cidade').fill('Belo Horizonte');
  await pagina.getByLabel(/Estado/).fill('MG');
  await pagina.getByRole('button', { name: 'Continuar' }).click();
  await pagina.getByRole('heading', { name: 'Confirmar assinatura' }).waitFor();
  passo('endereço salvo; etapa 4 (confirmação) com o resumo por entrega');
  assert.match(await pagina.locator('.lista-dados').first().innerText(), /por entrega/);

  // 5. Confirmação
  await pagina.getByRole('button', { name: 'Confirmar assinatura' }).click();
  await pagina.waitForURL(/\/\?nova=1/);
  await pagina.getByRole('heading', { name: 'Assinatura criada!' }).waitFor();
  passo('assinatura criada, com a data da 1ª entrega e como pagar');

  // 6. Funil (o beacon do site e o fetch do cadastro são assíncronos)
  let depois = contarFunil();
  for (let i = 0; i < 10 && depois && Number(depois.conta_criada ?? 0) <= Number(antes?.conta_criada ?? 0); i++) {
    await pagina.waitForTimeout(300);
    depois = contarFunil();
  }
  if (depois && antes) {
    for (const etapa of ['plano_clicado', 'conta_criada', 'endereco_salvo', 'assinatura_confirmada']) {
      assert.equal(Number(depois[etapa] ?? 0) - Number(antes[etapa] ?? 0), 1, `funil: ${etapa} deveria subir 1`);
    }
    passo('funil contou 1 em cada uma das 4 etapas');
  } else {
    console.log('  – funil não conferido (sem DATABASE_TEST_URL)');
  }
  console.log('\nE2E da assinatura: tudo passou.');
} catch (erro) {
  await pagina.screenshot({ path: 'e2e-falha.png', fullPage: true }).catch(() => {});
  console.error('\n✘ E2E falhou (screenshot em e2e-falha.png):', erro.message);
  process.exitCode = 1;
} finally {
  await navegador.close();
}
