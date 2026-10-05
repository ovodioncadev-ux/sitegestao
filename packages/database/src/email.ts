import 'server-only';

import { envOpcional } from './env';

/**
 * ═══════════════════════════════════════════════════════════════════════
 * Envio de e-mail transacional.
 *
 * Hoje só o e-mail de confirmação de conta usa isto. O provedor NÃO foi
 * escolhido pelo dono: este adaptador fala com a API HTTP do Resend
 * (sem dependência nova) e só liga quando as DUAS variáveis existem:
 *
 *   RESEND_API_KEY     chave do provedor
 *   EMAIL_REMETENTE    "Ovo di Onça <nao-responda@seu-dominio>" — o domínio
 *                      precisa estar verificado no provedor
 *
 * Sem elas, `emailConfigurado` é false, nenhum e-mail é enviado e o sistema
 * NÃO exige confirmação de e-mail (senão ninguém conseguiria entrar). Trocar
 * de provedor é trocar só esta função.
 * ═══════════════════════════════════════════════════════════════════════
 */

const chave = envOpcional('RESEND_API_KEY');
const remetente = envOpcional('EMAIL_REMETENTE');

export const emailConfigurado = Boolean(chave && remetente);

export async function enviarEmail(dados: { para: string; assunto: string; texto: string }): Promise<void> {
  if (!chave || !remetente) {
    // Nunca finge que enviou: quem chamou precisa saber que não há serviço.
    throw new Error('Serviço de e-mail não configurado (RESEND_API_KEY / EMAIL_REMETENTE).');
  }

  const resposta = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${chave}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: remetente, to: [dados.para], subject: dados.assunto, text: dados.texto }),
    signal: AbortSignal.timeout(10_000),
  });

  if (!resposta.ok) {
    // O corpo pode conter o endereço do destinatário: registra só o status.
    throw new Error(`O provedor de e-mail recusou o envio (HTTP ${resposta.status}).`);
  }
}
