import Link from 'next/link';
import { FormAcao } from '../_componentes/form-acao';
import { responderSolicitacao } from './acoes';
import { TIPO_SOLICITACAO, rotulo } from '@/lib/rotulos';

export type Solicitacao = {
  id: string;
  tipo: string;
  motivo: string | null;
  preferencia?: string | null;
  plano_destino_nome?: string | null;
  duzias_pedidas?: number | null;
  criado_em: string;
  cliente_nome: string;
  assinatura_id: string;
  assinatura_status: string;
};

/**
 * Pedidos de pausa/cancelamento feitos pelo assinante. O dono atende (e pode
 * já executar) ou recusa; a resposta fica gravada e na auditoria.
 */
export function SolicitacoesPendentes({
  solicitacoes,
  hoje,
  mostrarCliente = false,
}: {
  solicitacoes: Solicitacao[];
  hoje: string;
  mostrarCliente?: boolean;
}) {
  if (solicitacoes.length === 0) return <p className="suave">Nenhum pedido aguardando resposta.</p>;

  return (
    <div className="tabela-rolavel">
      <table>
        <thead>
          <tr>
            {mostrarCliente && <th>Cliente</th>}
            <th>Pedido</th>
            <th>Motivo</th>
            <th>Feito em</th>
            <th>Responder</th>
          </tr>
        </thead>
        <tbody>
          {solicitacoes.map((s) => {
            // Pausa só executa em assinatura ativa; cancelamento, em ativa ou pausada.
            const podeExecutar =
              s.tipo === 'cancelamento' ? ['ativa', 'pausada'].includes(s.assinatura_status) : s.assinatura_status === 'ativa';
            return (
              <tr key={s.id}>
                {mostrarCliente && (
                  <td>
                    <Link href={`/assinaturas/${s.assinatura_id}`}>{s.cliente_nome}</Link>
                  </td>
                )}
                <td>
                  {rotulo(TIPO_SOLICITACAO, s.tipo)}
                  {s.tipo === 'troca_plano' && s.plano_destino_nome ? ` → ${s.plano_destino_nome}` : ''}
                  {s.tipo === 'duzia' && s.duzias_pedidas !== null && s.duzias_pedidas !== undefined
                    ? `: ${s.duzias_pedidas === 0 ? 'parar de receber' : `${s.duzias_pedidas} por entrega`}`
                    : ''}
                  {s.tipo === 'pausa' && s.preferencia
                    ? ` (${s.preferencia === 'pentes' ? 'quer receber os pentes depois' : 'prefere crédito'})`
                    : ''}
                </td>
                <td>{s.motivo ?? '—'}</td>
                <td>{s.criado_em}</td>
                <td>
                  <details>
                    <summary>Atender</summary>
                    <FormAcao acao={responderSolicitacao} rotulo="Atender pedido">
                      <input type="hidden" name="solicitacao_id" value={s.id} />
                      <input type="hidden" name="resposta" value="atendida" />
                      {podeExecutar ? (
                        <label>
                          <input type="checkbox" name="executar" defaultChecked />{' '}
                          {s.tipo === 'pausa'
                            ? 'Pausar a assinatura agora'
                            : s.tipo === 'duzia'
                              ? 'Aplicar as dúzias a partir da próxima entrega depois do corte'
                              : s.tipo === 'troca_plano'
                              ? 'Trocar o plano agora (aumento vale já; redução, no mês seguinte)'
                              : 'Cancelar (no fim do mês pago)'}
                        </label>
                      ) : (
                        <p className="suave">A assinatura já não está numa situação em que o pedido se aplica.</p>
                      )}
                      {s.tipo === 'pausa' && podeExecutar && (
                        <>
                          <label htmlFor={`rp-${s.id}`}>Retorno previsto (opcional)</label>
                          <input id={`rp-${s.id}`} name="retorno_previsto" type="date" min={hoje} />
                        </>
                      )}
                      <label htmlFor={`ta-${s.id}`}>Mensagem (opcional)</label>
                      <input id={`ta-${s.id}`} name="texto" maxLength={500} />
                    </FormAcao>
                  </details>
                  <details>
                    <summary>Recusar</summary>
                    <FormAcao acao={responderSolicitacao} rotulo="Recusar pedido">
                      <input type="hidden" name="solicitacao_id" value={s.id} />
                      <input type="hidden" name="resposta" value="recusada" />
                      <label htmlFor={`tr-${s.id}`}>Motivo da recusa (opcional)</label>
                      <input id={`tr-${s.id}`} name="texto" maxLength={500} />
                    </FormAcao>
                  </details>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
