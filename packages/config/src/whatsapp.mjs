/**
 * Telefone do WhatsApp da Ovo di Onça — A ÚNICA fonte no código.
 *
 * Valor decidido em DECISOES.md (D12): (31) 2516-7561, com WhatsApp Business
 * confirmado. Trocar o número é mudar SÓ a linha abaixo: o texto exibido e o
 * link `wa.me` são derivados dela, e nenhum outro arquivo pode ter o número
 * escrito (apps/assinante/tests/whatsapp.test.ts reprova o build se tiver).
 */

/** Formato internacional (E.164 sem o "+"): país 55 + DDD + número. */
export const WHATSAPP_E164 = '553125167561';

/** "(31) 2516-7561" — derivado do E.164, para nunca divergir do link. */
export const WHATSAPP_EXIBICAO = formatarNacional(WHATSAPP_E164);

/** Link de conversa. Aceita uma mensagem inicial opcional. */
export function urlWhatsapp(mensagem) {
  const base = `https://wa.me/${WHATSAPP_E164}`;
  return mensagem ? `${base}?text=${encodeURIComponent(mensagem)}` : base;
}

export const WHATSAPP_URL = urlWhatsapp();

/**
 * Link de conversa com UMA PESSOA (cliente ou interessado), a partir do telefone
 * nacional (DDD + número, 10 ou 11 dígitos). É o outro sentido do link acima: aqui
 * o número é o da pessoa, não o da Ovo di Onça. Fica neste arquivo para que `wa.me`
 * continue escrito num lugar só.
 */
export function urlWhatsappDe(telefoneNacional, mensagem) {
  const digitos = String(telefoneNacional).replace(/\D/g, '');
  const base = `https://wa.me/55${digitos}`;
  return mensagem ? `${base}?text=${encodeURIComponent(mensagem)}` : base;
}

/** 55 + DDD(2) + número(8 ou 9) → "(DD) NNNN-NNNN" ou "(DD) NNNNN-NNNN". */
export function formatarNacional(e164) {
  const d = String(e164).replace(/\D/g, '').replace(/^55/, '');
  const ddd = d.slice(0, 2);
  const numero = d.slice(2);
  const corte = numero.length - 4;
  return `(${ddd}) ${numero.slice(0, corte)}-${numero.slice(corte)}`;
}
