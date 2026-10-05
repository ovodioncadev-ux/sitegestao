import { criarInfinitePay } from './infinitepay.ts';
import { criarSimulado } from './simulado.ts';
import type { ProvedorPagamento } from './tipos.ts';

/** Endereço público do app do assinante (o provedor chama o aviso aqui; a pessoa volta para cá). */
export function urlPublicaDoAssinante(env: NodeJS.ProcessEnv = process.env): string {
  return env.URL_PUBLICA_ASSINANTE ?? env.BETTER_AUTH_URL ?? 'http://localhost:3001';
}

/**
 * Provedor escolhido por PAGAMENTO_PROVEDOR (nenhum | simulado | infinitepay).
 * Padrão: nenhum — o pagamento segue manual (PIX com comprovante) e nada muda.
 * O simulador é recusado em produção.
 */
export function obterProvedor(env: NodeJS.ProcessEnv = process.env): ProvedorPagamento | null {
  const escolhido = (env.PAGAMENTO_PROVEDOR ?? 'nenhum').trim().toLowerCase();

  if (escolhido === 'nenhum' || escolhido === '') return null;

  if (escolhido === 'simulado') {
    if (env.NODE_ENV === 'production') {
      throw new Error('PAGAMENTO_PROVEDOR=simulado não pode ser usado em produção.');
    }
    const segredo = env.PAGAMENTO_SIMULADO_SEGREDO;
    if (!segredo || segredo.length < 16) {
      throw new Error('PAGAMENTO_SIMULADO_SEGREDO precisa ter ao menos 16 caracteres.');
    }
    return criarSimulado({ segredo, urlPublica: urlPublicaDoAssinante(env) });
  }

  if (escolhido === 'infinitepay') {
    return criarInfinitePay({
      handle: (env.INFINITEPAY_HANDLE ?? '').replace(/^\$/, '').trim(),
      contratoConfirmado: env.INFINITEPAY_CONTRATO_CONFIRMADO === 'sim',
    });
  }

  throw new Error(`PAGAMENTO_PROVEDOR desconhecido: ${escolhido}`);
}

/** `true` se há provedor configurado e válido. Nunca lança: serve para decidir se mostra "Pagar agora". */
export function pagamentoOnlineAtivo(env: NodeJS.ProcessEnv = process.env): boolean {
  try {
    return obterProvedor(env) !== null;
  } catch (erro) {
    console.error('[pagamento] configuração inválida:', erro instanceof Error ? erro.message : erro);
    return false;
  }
}
