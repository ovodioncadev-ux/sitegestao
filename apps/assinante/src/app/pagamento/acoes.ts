'use server';

import { redirect } from 'next/navigation';
import { comoAssinante } from '@/lib/assinante';
import { ErroNegocio, rodar } from '@/lib/erros';
import { obterProvedor, urlPublicaDoAssinante } from '@/lib/pagamento/provedor';
import type { Estado } from '@/lib/tipos';
import { campo, uuid } from '@/lib/validacao';

/**
 * "Pagar agora": leva a pessoa ao pagamento online da PRÓPRIA fatura.
 *
 * O id da fatura vem do formulário, mas o banco só devolve dados se a fatura é da
 * conta da sessão e está em aberto (iniciar_pagamento_online). O valor cobrado é o
 * da fatura no banco, nunca um número do navegador. O link gerado fica guardado na
 * fatura e é reaproveitado.
 */
export async function pagarFatura(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const faturaId = uuid(campo(dados, 'fatura'), 'Fatura');

    const provedor = obterProvedor();
    if (!provedor) {
      throw new ErroNegocio(
        'O pagamento online ainda não está disponível. Envie o comprovante do PIX pelo WhatsApp e a Ovo di Onça confirma.',
      );
    }

    const info = await comoAssinante((bd) =>
      bd.umaLinha<{ valor_centavos: number; referencia: string; link_existente: string | null }>(
        'select valor_centavos, referencia, link_existente from iniciar_pagamento_online($1)',
        [faturaId],
      ),
    );
    if (!info) throw new ErroNegocio('Fatura não encontrada ou já paga.');

    let url = info.link_existente;
    if (!url) {
      const base = urlPublicaDoAssinante();
      const link = await provedor.criarLink({
        faturaId: info.referencia,
        valorCentavos: info.valor_centavos,
        descricao: 'Assinatura Ovo di Onça',
        urlRetorno: `${base}/`,
        urlAviso: `${base}/api/pagamento/webhook`,
      });
      url = link.url;
      // O banco só aceita link https. O simulador local (http://localhost) não é guardado:
      // é descartável e cada clique gera o mesmo endereço.
      if (url.startsWith('https://')) {
        const guardar = url;
        await comoAssinante((bd) => bd.consultar('select anexar_link_pagamento($1, $2)', [faturaId, guardar]));
      }
    }

    redirect(url);
  });
}
