import { notFound } from 'next/navigation';
import { formatarReais } from '@/lib/formatar';
import { pagamentoOnlineAtivo, obterProvedor } from '@/lib/pagamento/provedor';
import { FormAcao } from '../../../_componentes/form-acao';
import { simularPagamento } from './acoes';

export const dynamic = 'force-dynamic';

/** Página do "provedor" de mentira. Só existe com PAGAMENTO_PROVEDOR=simulado fora de produção. */
export default async function PagamentoSimulado({
  params,
  searchParams,
}: {
  params: Promise<{ fatura: string }>;
  searchParams: Promise<{ valor?: string }>;
}) {
  if (!pagamentoOnlineAtivo() || obterProvedor()?.nome !== 'simulado') notFound();
  const { fatura } = await params;
  const { valor } = await searchParams;
  const centavos = Number(valor);
  if (!Number.isInteger(centavos) || centavos < 0) notFound();

  return (
    <main className="estreito">
      <h1>Pagamento simulado</h1>
      <p className="msg-info">Ambiente de desenvolvimento: nenhum dinheiro de verdade é cobrado.</p>
      <section className="cartao">
        <p>
          Valor: <strong>{formatarReais(centavos)}</strong>
        </p>
        <FormAcao acao={simularPagamento} rotulo="Simular pagamento aprovado">
          <input type="hidden" name="fatura" value={fatura} />
          <input type="hidden" name="valor" value={centavos} />
          <input type="hidden" name="metodo" value="pix" />
        </FormAcao>
      </section>
    </main>
  );
}
