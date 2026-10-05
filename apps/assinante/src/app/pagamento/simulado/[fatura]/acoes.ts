'use server';

import { randomUUID } from 'node:crypto';
import { redirect } from 'next/navigation';
import { ErroNegocio, rodar } from '@/lib/erros';
import { obterProvedor, urlPublicaDoAssinante } from '@/lib/pagamento/provedor';
import { assinarSimulado } from '@/lib/pagamento/simulado';
import type { Estado } from '@/lib/tipos';
import { campo, uuid } from '@/lib/validacao';

/**
 * SÓ DESENVOLVIMENTO. Faz o papel do provedor: assina um aviso e o entrega ao
 * webhook de verdade (HTTP), como um provedor real faria. Recusa qualquer outro modo.
 */
export async function simularPagamento(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const provedor = obterProvedor();
    const segredo = process.env.PAGAMENTO_SIMULADO_SEGREDO;
    if (provedor?.nome !== 'simulado' || !segredo) throw new ErroNegocio('Simulador desligado.');

    const fatura = uuid(campo(dados, 'fatura'), 'Fatura');
    const valor = Number(campo(dados, 'valor'));
    if (!Number.isInteger(valor) || valor < 0) throw new ErroNegocio('Valor inválido.');
    const metodo = campo(dados, 'metodo') === 'cartao' ? 'cartao' : 'pix';
    const transacao = `sim-${randomUUID()}`;

    const res = await fetch(`${urlPublicaDoAssinante()}/api/pagamento/webhook`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        fatura,
        transacao,
        valor,
        metodo,
        assinatura: assinarSimulado(segredo, fatura, transacao, valor, metodo),
      }),
    });
    if (!res.ok) throw new ErroNegocio(`O webhook recusou o aviso (HTTP ${res.status}).`);
    redirect('/');
  });
}
