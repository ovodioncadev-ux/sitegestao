import { test } from 'node:test';
import assert from 'node:assert/strict';
import { processarAviso, type ConfirmacaoNoBanco } from '../src/lib/pagamento/aviso.ts';
import { criarInfinitePay } from '../src/lib/pagamento/infinitepay.ts';
import { obterProvedor } from '../src/lib/pagamento/provedor.ts';
import { assinarSimulado, criarSimulado } from '../src/lib/pagamento/simulado.ts';
import type { ProvedorPagamento } from '../src/lib/pagamento/tipos.ts';

const FATURA = '3f1c2a52-8b6e-4c3a-9d3e-1a2b3c4d5e6f';
/** Monta um `process.env` de mentira (NODE_ENV é somente leitura no tipo real). */
const e = (o: Record<string, string>) => o as unknown as NodeJS.ProcessEnv;
const SEGREDO = 'segredo-de-teste-com-mais-de-16';
const simulado = criarSimulado({ segredo: SEGREDO, urlPublica: 'http://localhost:3001' });

function aviso(valor: number, assinaturaValor = valor) {
  return {
    fatura: FATURA,
    transacao: 'tx-1',
    valor,
    metodo: 'pix',
    assinatura: assinarSimulado(SEGREDO, FATURA, 'tx-1', assinaturaValor, 'pix'),
  };
}

function espiao() {
  const chamadas: Parameters<ConfirmacaoNoBanco>[0][] = [];
  const confirmar: ConfirmacaoNoBanco = async (dados) => {
    chamadas.push(dados);
    return 'confirmado';
  };
  return { chamadas, confirmar };
}

test('aviso legítimo: consulta o provedor e confirma com os dados DELE', async () => {
  const { chamadas, confirmar } = espiao();
  const r = await processarAviso(simulado, aviso(14760), confirmar);
  assert.deepEqual(r, { tipo: 'processado', resultado: 'confirmado' });
  assert.deepEqual(chamadas, [
    { faturaId: FATURA, provedor: 'simulado', transacaoId: 'tx-1', valorPagoCentavos: 14760, metodo: 'pix' },
  ]);
});

test('aviso forjado (valor adulterado depois de assinado) NUNCA chega ao banco', async () => {
  const { chamadas, confirmar } = espiao();
  // O atacante muda o valor para 1 centavo mantendo a assinatura do valor original.
  const r = await processarAviso(simulado, aviso(1, 14760), confirmar);
  assert.deepEqual(r, { tipo: 'nao_pago' });
  assert.equal(chamadas.length, 0);
});

test('aviso sem assinatura válida ou com lixo é inválido ou não pago, e não confirma', async () => {
  const { chamadas, confirmar } = espiao();
  for (const corpo of [null, undefined, 'texto', 42, [], {}, { fatura: 'nao-e-uuid' }]) {
    assert.equal((await processarAviso(simulado, corpo, confirmar)).tipo, 'invalido', JSON.stringify(corpo));
  }
  const semAssinatura = { ...aviso(14760), assinatura: 'x'.repeat(10) };
  assert.equal((await processarAviso(simulado, semAssinatura, confirmar)).tipo, 'nao_pago');
  assert.equal(chamadas.length, 0);
});

test('o que vale é o que o provedor devolve, não o que o corpo diz', async () => {
  const { chamadas, confirmar } = espiao();
  const provedor: ProvedorPagamento = {
    nome: 'falso',
    criarLink: async () => ({ url: 'https://x.test' }),
    lerAviso: () => ({ faturaId: FATURA, dadosDeConsulta: {} }),
    conferir: async () => ({ pago: true, transacaoId: 'tx-real', valorPagoCentavos: 500, metodo: 'cartao' }),
  };
  // O corpo alega R$ 1.000.000; o provedor confirma R$ 5,00.
  await processarAviso(provedor, { valor: 100000000, paid: true }, confirmar);
  assert.equal(chamadas[0]?.valorPagoCentavos, 500);
  assert.equal(chamadas[0]?.transacaoId, 'tx-real');
  assert.equal(chamadas[0]?.metodo, 'cartao');
});

test('provedor fora do ar: "indisponivel" (para ele reenviar) e nada é confirmado', async () => {
  const { chamadas, confirmar } = espiao();
  const provedor: ProvedorPagamento = {
    nome: 'caido',
    criarLink: async () => ({ url: 'https://x.test' }),
    lerAviso: () => ({ faturaId: FATURA, dadosDeConsulta: {} }),
    conferir: async () => {
      throw new Error('timeout');
    },
  };
  const erro = console.error;
  console.error = () => {};
  try {
    assert.deepEqual(await processarAviso(provedor, {}, confirmar), { tipo: 'indisponivel' });
  } finally {
    console.error = erro;
  }
  assert.equal(chamadas.length, 0);
});

test('provedor diz que não está pago: nada é confirmado', async () => {
  const { chamadas, confirmar } = espiao();
  const provedor: ProvedorPagamento = {
    nome: 'pendente',
    criarLink: async () => ({ url: 'https://x.test' }),
    lerAviso: () => ({ faturaId: FATURA, dadosDeConsulta: {} }),
    conferir: async () => ({ pago: false, transacaoId: 't', valorPagoCentavos: 0, metodo: 'pix' }),
  };
  assert.deepEqual(await processarAviso(provedor, {}, confirmar), { tipo: 'nao_pago' });
  assert.equal(chamadas.length, 0);
});

test('obterProvedor: padrão é nenhum (pagamento manual)', () => {
  assert.equal(obterProvedor(e({})), null);
  assert.equal(obterProvedor(e({ PAGAMENTO_PROVEDOR: 'nenhum' })), null);
});

test('obterProvedor: o simulador é recusado em produção e exige segredo forte', () => {
  const base = { PAGAMENTO_PROVEDOR: 'simulado', PAGAMENTO_SIMULADO_SEGREDO: SEGREDO };
  assert.equal(obterProvedor(e({ ...base, NODE_ENV: 'development' }))?.nome, 'simulado');
  assert.throws(() => obterProvedor(e({ ...base, NODE_ENV: 'production' })), /produção/);
  assert.throws(
    () => obterProvedor(e({ PAGAMENTO_PROVEDOR: 'simulado', PAGAMENTO_SIMULADO_SEGREDO: 'curto' })),
    /16 caracteres/,
  );
});

test('obterProvedor: a InfinitePay só liga com o contrato confirmado e com o handle', () => {
  assert.throws(() => obterProvedor(e({ PAGAMENTO_PROVEDOR: 'infinitepay', INFINITEPAY_HANDLE: 'loja' })), /não confirmado/);
  assert.throws(
    () => obterProvedor(e({ PAGAMENTO_PROVEDOR: 'infinitepay', INFINITEPAY_CONTRATO_CONFIRMADO: 'sim' })),
    /INFINITEPAY_HANDLE/,
  );
  const ok = obterProvedor(e({
    PAGAMENTO_PROVEDOR: 'infinitepay',
    INFINITEPAY_CONTRATO_CONFIRMADO: 'sim',
    INFINITEPAY_HANDLE: '$minha-loja',
  }));
  assert.equal(ok?.nome, 'infinitepay');
  assert.throws(() => obterProvedor(e({ PAGAMENTO_PROVEDOR: 'outro' })), /desconhecido/);
});

test('InfinitePay.lerAviso: exige o id da fatura (UUID) e o transaction_nsu; não repassa valores do corpo', () => {
  const p = criarInfinitePay({ handle: 'loja', contratoConfirmado: true });
  assert.equal(p.lerAviso({ order_nsu: 'abc', transaction_nsu: 't' }), null);
  assert.equal(p.lerAviso({ order_nsu: FATURA }), null);
  assert.equal(p.lerAviso(null), null);
  const lido = p.lerAviso({ order_nsu: FATURA, transaction_nsu: 'tx-9', invoice_slug: 's', paid_amount: 99999999, amount: 1 });
  assert.deepEqual(lido, { faturaId: FATURA, dadosDeConsulta: { transaction_nsu: 'tx-9', invoice_slug: 's' } });
});

test('simulado.criarLink aponta para a página de simulação da própria fatura', async () => {
  const { url } = await simulado.criarLink({
    faturaId: FATURA,
    valorCentavos: 14760,
    descricao: 'x',
    urlRetorno: 'http://localhost:3001/',
    urlAviso: 'http://localhost:3001/api/pagamento/webhook',
  });
  assert.equal(url, `http://localhost:3001/pagamento/simulado/${FATURA}?valor=14760`);
});
