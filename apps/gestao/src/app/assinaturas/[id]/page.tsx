import Link from 'next/link';
import { notFound } from 'next/navigation';
import { comoAdmin, comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { FormAcao } from '../../_componentes/form-acao';
import { Pagina, SemPermissao } from '../../_componentes/pagina';
import {
  alterarPlanoAssinatura,
  cancelarAssinatura,
  definirFormaCobranca,
  desfazerCancelamentoAgendado,
  gerarProximaCobranca,
  pausarAssinatura,
  reativarAssinatura,
} from '../acoes';
import { SolicitacoesPendentes, type Solicitacao } from '../solicitacoes';
import { AcoesDaEntrega } from '../../entregas/acoes-entrega';
import { agendarEntrega, cancelarReposicao } from '../../entregas/acoes';
import { AcoesDaFatura } from '../../faturas/acoes-fatura';
import { criarFatura } from '../../faturas/acoes';
import { centavosParaCampo, formatarData, formatarReais, hojeEmSaoPaulo } from '@/lib/formatar';
import {
  CHAVES_FORMA_COBRANCA,
  FORMA_COBRANCA,
  METODO_PAGAMENTO,
  STATUS_ASSINATURA,
  STATUS_ENTREGA,
  STATUS_FATURA,
  STATUS_REPOSICAO,
  STATUS_SOLICITACAO,
  TIPO_SOLICITACAO,
  rotulo,
} from '@/lib/rotulos';
import { uuid } from '@/lib/validacao';

type Assinatura = {
  id: string;
  cliente_id: string;
  cliente_nome: string;
  plano_id: number;
  plano_nome: string;
  status: string;
  data_inicio: string;
  data_fim: string | null;
  proxima_entrega: string | null;
  data_cancelamento: string | null;
  motivo_cancelamento: string | null;
  forma_cobranca: string;
  proxima_cobranca: string | null;
  pausada_em: string | null;
  data_retorno_prevista: string | null;
  aguardando_pagamento_desde: string | null;
  bloqueada_desde: string | null;
  cancelamento_agendado_para: string | null;
  plano_proximo_nome: string | null;
  plano_proximo_a_partir_de: string | null;
  saldo_credito: number;
  dias_pausa: number | null;
  dias_max_pausa: number;
};

type ReposicaoLinha = {
  id: string;
  quantidade_ovos: number;
  descricao: string;
  status: string;
  origem: string;
  reposicao: string | null;
  reposta_em: string | null;
};

type EntregaLinha = {
  id: string;
  data_prevista: string;
  data_realizada: string | null;
  status: string;
  observacao: string | null;
  pentes: number;
  duzias: number;
  horario_previsto: string | null;
};

type FaturaLinha = {
  id: string;
  valor_centavos: number;
  vencimento: string;
  data_pagamento: string | null;
  status: string;
  metodo: string | null;
  observacao: string | null;
  periodo_inicio: string | null;
  periodo_fim: string | null;
};

export default async function DetalheAssinatura({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  try {
    uuid(id, 'Assinatura');
  } catch {
    notFound();
  }

  // O valor sugerido da próxima fatura só o banco sabe calcular (função sem grant
  // para o papel de leitura). exigirDono() já aprovou acima; roda em paralelo com a
  // leitura da página em vez de esperar por ela (cada ida ao banco custa ~150 ms).
  const valorSugeridoPromessa = comoAdmin((bd) =>
    bd.umaLinha<{ v: number }>('select calcular_valor_fatura($1::uuid) as v', [id]),
  ).then(
    (linha) => linha?.v ?? null,
    () => null, // assinatura inexistente ou sem cálculo possível: só não sugere valor
  );

  const { assinatura, planos, entregas, faturas, reposicoes, pedidos } = await comoUsuario(autorizacao.usuario.usuarioId, async (bd) => {
    const assinatura = await bd.umaLinha<Assinatura>(
      `select a.id, a.cliente_id, c.nome as cliente_nome, a.plano_id, p.nome as plano_nome,
              a.status::text, a.data_inicio::text, a.data_fim::text, a.proxima_entrega::text,
              a.data_cancelamento::text, a.motivo_cancelamento, a.forma_cobranca::text,
              a.proxima_cobranca::text, a.pausada_em::text, a.data_retorno_prevista::text,
              a.aguardando_pagamento_desde::text, a.bloqueada_desde::text,
              a.cancelamento_agendado_para::text, pp.nome as plano_proximo_nome, a.plano_proximo_a_partir_de::text,
              (select coalesce(sum(cr.valor_centavos), 0)::int from creditos_assinatura cr where cr.assinatura_id = a.id) as saldo_credito,
              case when a.status = 'pausada' then (hoje_ref.d - a.pausada_em)::int end as dias_pausa,
              cfg.dias_max_pausa
         from assinaturas a
         join clientes c on c.id = a.cliente_id
         join planos p on p.id = a.plano_id
         left join planos pp on pp.id = a.plano_proximo_id
         cross join config_negocio cfg
         cross join (select (now() at time zone 'America/Sao_Paulo')::date as d) hoje_ref
        where a.id = $1 and cfg.id = 1`,
      [id],
    );
    const planos = await bd.consultar<{ id: number; nome: string }>(
      'select id, nome from planos where ativo order by intervalo_dias',
    );
    const entregas = await bd.consultar<EntregaLinha>(
      `select id, data_prevista::text, to_char(data_realizada at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') as data_realizada,
              status::text, observacao, pentes, duzias, to_char(horario_previsto, 'HH24:MI') as horario_previsto
         from entregas where assinatura_id = $1
        order by data_prevista desc, criado_em desc`,
      [id],
    );
    const faturas = await bd.consultar<FaturaLinha>(
      `select id, valor_centavos, vencimento::text, data_pagamento::text, status::text, metodo::text, observacao,
              periodo_inicio::text, periodo_fim::text
         from faturas where assinatura_id = $1
        order by vencimento desc, criado_em desc`,
      [id],
    );
    const reposicoes = await bd.consultar<ReposicaoLinha>(
      `select r.id, r.quantidade_ovos, r.descricao, r.status::text,
              o.data_prevista::text as origem, d.data_prevista::text as reposicao,
              to_char(r.reposta_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') as reposta_em
         from reposicoes r
         join entregas o on o.id = r.entrega_origem_id
         left join entregas d on d.id = r.entrega_reposicao_id
        where r.assinatura_id = $1
        order by r.criado_em desc`,
      [id],
    );
    const pedidos = await bd.consultar<Solicitacao & { status: string; resposta: string | null; resolvida_em: string | null }>(
      `select s.id, s.tipo::text, s.motivo, s.preferencia, s.duzias_pedidas, pd.nome as plano_destino_nome, to_char(s.criado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') as criado_em,
              c.nome as cliente_nome, s.assinatura_id, a.status::text as assinatura_status,
              s.status::text, s.resposta,
              to_char(s.resolvida_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') as resolvida_em
         from solicitacoes_assinatura s
         join clientes c on c.id = s.cliente_id
         join assinaturas a on a.id = s.assinatura_id
         left join planos pd on pd.id = s.plano_destino_id
        where s.assinatura_id = $1
        order by s.criado_em desc`,
      [id],
    );
    return { assinatura, planos, entregas, faturas, reposicoes, pedidos };
  });

  if (!assinatura) notFound();

  const vigente = assinatura.status === 'ativa' || assinatura.status === 'pausada';
  const hoje = hojeEmSaoPaulo();
  const aguardando = Boolean(assinatura.aguardando_pagamento_desde) && assinatura.status === 'ativa';
  // "Sem próxima entrega" é alerta; aguardar o 1º pagamento é esperado (D8) e tem aviso próprio.
  const bloqueada = Boolean(assinatura.bloqueada_desde);
  const semProxima = assinatura.status === 'ativa' && !assinatura.proxima_entrega && !aguardando && !bloqueada;

  // Valor sugerido para a próxima fatura (regra única, calculada pelo banco).
  const valorSugerido = assinatura.status === 'ativa' ? await valorSugeridoPromessa : null;

  return (
    <Pagina titulo={`Assinatura de ${assinatura.cliente_nome}`}>
      <p>
        <Link href="/assinaturas">← Assinaturas</Link> ·{' '}
        <Link href={`/clientes/${assinatura.cliente_id}`}>Ver cliente</Link> ·{' '}
        <Link href={`/historico?entidade=assinaturas&id=${assinatura.id}`}>Ver histórico</Link>
      </p>

      <table>
        <tbody>
          <tr>
            <th>Situação</th>
            <td>{bloqueada ? 'Ativa, bloqueada por inadimplência' : rotulo(STATUS_ASSINATURA, assinatura.status)}</td>
          </tr>
          <tr>
            <th>Plano</th>
            <td>{assinatura.plano_nome}</td>
          </tr>
          <tr>
            <th>Início</th>
            <td>{formatarData(assinatura.data_inicio)}</td>
          </tr>
          <tr>
            <th>Próxima entrega</th>
            <td>
              {bloqueada
                ? `Paradas por inadimplência desde ${formatarData(assinatura.bloqueada_desde)}: voltam quando as faturas em atraso forem pagas`
                : aguardando
                ? `Aguardando o 1º pagamento (desde ${formatarData(assinatura.aguardando_pagamento_desde)}): registre o pagamento da 1ª fatura para agendar a entrega`
                : formatarData(assinatura.proxima_entrega)}
            </td>
          </tr>
          <tr>
            <th>Forma de cobrança</th>
            <td>{rotulo(FORMA_COBRANCA, assinatura.forma_cobranca)}</td>
          </tr>
          <tr>
            <th>Próxima cobrança</th>
            <td>{assinatura.status === 'ativa' ? formatarData(assinatura.proxima_cobranca) : '— (parada)'}</td>
          </tr>
          {assinatura.cancelamento_agendado_para && (
            <tr>
              <th>Cancelamento</th>
              <td>
                <strong>Agendado:</strong> vale até {formatarData(assinatura.cancelamento_agendado_para)} (fim do mês pago).
                Entregas continuam até lá; sem cobrança nova.
              </td>
            </tr>
          )}
          {assinatura.plano_proximo_nome && (
            <tr>
              <th>Troca de plano</th>
              <td>
                Passa para <strong>{assinatura.plano_proximo_nome}</strong> em {formatarData(assinatura.plano_proximo_a_partir_de)}
              </td>
            </tr>
          )}
          {assinatura.saldo_credito !== 0 && (
            <tr>
              <th>Crédito</th>
              <td>{formatarReais(assinatura.saldo_credito)} (abate a próxima fatura sem desconto percentual)</td>
            </tr>
          )}
          {assinatura.status === 'pausada' && (
            <tr>
              <th>Pausa</th>
              <td>
                desde {formatarData(assinatura.pausada_em)}
                {assinatura.data_retorno_prevista
                  ? ` · retorno previsto em ${formatarData(assinatura.data_retorno_prevista)} (automático)`
                  : ' · sem data de retorno'}
              </td>
            </tr>
          )}
          {assinatura.data_cancelamento && (
            <tr>
              <th>Cancelada em</th>
              <td>
                {formatarData(assinatura.data_cancelamento)}
                {assinatura.motivo_cancelamento ? ` — ${assinatura.motivo_cancelamento}` : ''}
              </td>
            </tr>
          )}
        </tbody>
      </table>

      {assinatura.status === 'pausada' && assinatura.dias_pausa !== null && assinatura.dias_pausa > assinatura.dias_max_pausa && (
        <p className="msg-erro" role="alert">
          Esta pausa já dura {assinatura.dias_pausa} dias (o limite é {assinatura.dias_max_pausa}). Decida: reative a
          assinatura ou cancele.
        </p>
      )}

      <h2>Situação da assinatura</h2>
      {assinatura.status === 'ativa' && (
        <>
          <details>
            <summary>Pausar assinatura</summary>
            <FormAcao acao={pausarAssinatura} rotulo="Pausar assinatura">
              <input type="hidden" name="assinatura_id" value={assinatura.id} />
              <label htmlFor="motivo-pausa">Motivo (opcional)</label>
              <input id="motivo-pausa" name="motivo" maxLength={500} />
              <label htmlFor="retorno-previsto">Retorno previsto (opcional)</label>
              <input id="retorno-previsto" name="retorno_previsto" type="date" min={hoje} />
              <label htmlFor="destino-pausa">Entregas já pagas e não feitas</label>
              <select id="destino-pausa" name="destino" defaultValue="credito">
                <option value="credito">Viram crédito na próxima fatura</option>
                <option value="pentes">O cliente recebe os pentes depois</option>
              </select>
            </FormAcao>
            <p className="suave">
              Entregas e faturas pendentes serão canceladas, a cobrança para e o cliente ficará “suspenso”. Com
              retorno previsto (no máximo {assinatura.dias_max_pausa} dias), a rotina diária reativa a assinatura nessa
              data. A fatura em aberto do mês fica só com as entregas já feitas.
            </p>
          </details>
          <details>
            <summary>Cancelar assinatura</summary>
            <FormAcao acao={cancelarAssinatura} rotulo="Cancelar assinatura">
              <input type="hidden" name="assinatura_id" value={assinatura.id} />
              <label htmlFor="motivo-cancelamento">Motivo (opcional)</label>
              <input id="motivo-cancelamento" name="motivo" maxLength={500} />
              <label>
                <input type="checkbox" name="imediato" /> Cancelar agora (sem esperar o fim do mês pago)
              </label>
            </FormAcao>
            <p className="suave">
              Por padrão, o cancelamento vale no fim do mês já pago: as entregas continuam até lá e nada novo é
              cobrado. O histórico é mantido.
            </p>
            {assinatura.cancelamento_agendado_para && (
              <FormAcao acao={desfazerCancelamentoAgendado} rotulo="Desfazer cancelamento agendado">
                <input type="hidden" name="assinatura_id" value={assinatura.id} />
              </FormAcao>
            )}
          </details>
        </>
      )}
      {assinatura.status === 'pausada' && (
        <>
          <details open>
            <summary>Reativar assinatura</summary>
            <FormAcao acao={reativarAssinatura} rotulo="Reativar assinatura">
              <input type="hidden" name="assinatura_id" value={assinatura.id} />
              <label htmlFor="retorno-p">Data de retorno (vazio = hoje)</label>
              <input id="retorno-p" name="retorno" type="date" min={hoje} />
            </FormAcao>
            <p className="suave">O calendário recomeça a partir dessa data, na próxima quarta-feira.</p>
          </details>
          <details>
            <summary>Cancelar assinatura</summary>
            <FormAcao acao={cancelarAssinatura} rotulo="Cancelar assinatura">
              <input type="hidden" name="assinatura_id" value={assinatura.id} />
              <label htmlFor="motivo-cancelamento-p">Motivo (opcional)</label>
              <input id="motivo-cancelamento-p" name="motivo" maxLength={500} />
            </FormAcao>
          </details>
        </>
      )}
      {assinatura.status === 'cancelada' && (
        <details open>
          <summary>Reativar assinatura cancelada</summary>
          <FormAcao acao={reativarAssinatura} rotulo="Reativar assinatura">
            <input type="hidden" name="assinatura_id" value={assinatura.id} />
            <label htmlFor="retorno-c">Data de retorno (vazio = hoje)</label>
            <input id="retorno-c" name="retorno" type="date" min={hoje} />
          </FormAcao>
          <p className="suave">
            O histórico anterior é mantido. O calendário recomeça a partir dessa data, na próxima quarta-feira.
          </p>
        </details>
      )}
      {assinatura.status === 'encerrada' && <p className="suave">Assinatura encerrada.</p>}

      {pedidos.some((p) => p.status === 'pendente') && (
        <>
          <h2>Pedidos do assinante aguardando resposta</h2>
          <SolicitacoesPendentes solicitacoes={pedidos.filter((p) => p.status === 'pendente')} hoje={hoje} />
        </>
      )}
      {pedidos.some((p) => p.status !== 'pendente') && (
        <details>
          <summary>Pedidos já respondidos</summary>
          <ul>
            {pedidos
              .filter((p) => p.status !== 'pendente')
              .map((p) => (
                <li key={p.id}>
                  {p.criado_em}: {rotulo(TIPO_SOLICITACAO, p.tipo)} — {rotulo(STATUS_SOLICITACAO, p.status)} em{' '}
                  {p.resolvida_em}
                  {p.resposta ? ` (“${p.resposta}”)` : ''}
                </li>
              ))}
          </ul>
        </details>
      )}

      <h2>Entregas</h2>
      {semProxima && (
        <p className="msg-erro">
          Assinatura ativa sem próxima entrega. Agende uma abaixo.
        </p>
      )}
      {entregas.length === 0 ? (
        <p>Nenhuma entrega registrada.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Data prevista</th>
                <th>Situação</th>
                <th>Quantidade</th>
                <th>Horário</th>
                <th>Realizada em</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {entregas.map((e) => (
                <tr key={e.id}>
                  <td>{formatarData(e.data_prevista)}</td>
                  <td>
                    {rotulo(STATUS_ENTREGA, e.status)}
                    {e.observacao ? <div className="suave">{e.observacao}</div> : null}
                  </td>
                  <td>
                    {e.pentes} pente(s){e.duzias > 0 ? ` + ${e.duzias} dúzia(s)` : ''}
                  </td>
                  <td>{e.horario_previsto ?? '—'}</td>
                  <td>{e.data_realizada ?? '—'}</td>
                  <td>
                    <AcoesDaEntrega
                      entregaId={e.id}
                      status={e.status}
                      observacao={e.observacao}
                      horario={e.horario_previsto}
                      hoje={hoje}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {assinatura.status === 'ativa' && (
        <>
          <h3>Agendar entrega</h3>
          <FormAcao acao={agendarEntrega} rotulo="Agendar entrega" linha>
            <input type="hidden" name="assinatura_id" value={assinatura.id} />
            <div>
              <label htmlFor="data-entrega">Data</label>
              <input id="data-entrega" name="data" type="date" defaultValue={hoje} required />
            </div>
          </FormAcao>
        </>
      )}

      <h2>Reposições (ovos com defeito)</h2>
      {reposicoes.length === 0 ? (
        <p className="suave">Nenhum defeito registrado. Para registrar, use “Registrar defeito” numa entrega já feita.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Entrega com defeito</th>
                <th>Ovos</th>
                <th>Descrição</th>
                <th>Situação</th>
                <th>Repor em</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {reposicoes.map((r) => (
                <tr key={r.id}>
                  <td>{formatarData(r.origem)}</td>
                  <td>{r.quantidade_ovos}</td>
                  <td>{r.descricao}</td>
                  <td>
                    {rotulo(STATUS_REPOSICAO, r.status)}
                    {r.reposta_em ? ` em ${r.reposta_em}` : ''}
                  </td>
                  <td>{r.reposicao ? formatarData(r.reposicao) : r.status === 'pendente' ? 'próxima entrega agendada' : '—'}</td>
                  <td>
                    {r.status === 'pendente' ? (
                      <details>
                        <summary>Cancelar reposição</summary>
                        <FormAcao acao={cancelarReposicao} rotulo="Cancelar reposição">
                          <input type="hidden" name="reposicao_id" value={r.id} />
                          <label htmlFor={`mr-${r.id}`}>Motivo (opcional)</label>
                          <input id={`mr-${r.id}`} name="motivo" maxLength={300} />
                        </FormAcao>
                      </details>
                    ) : (
                      '—'
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <h2>Cobrança</h2>
      {vigente && (
        <FormAcao acao={definirFormaCobranca} rotulo="Salvar forma de cobrança" linha>
          <input type="hidden" name="assinatura_id" value={assinatura.id} />
          <div>
            <label htmlFor="forma">Forma de cobrança</label>
            <select id="forma" name="forma" defaultValue={assinatura.forma_cobranca}>
              {CHAVES_FORMA_COBRANCA.map((f) => (
                <option key={f} value={f}>
                  {FORMA_COBRANCA[f]}
                </option>
              ))}
            </select>
          </div>
        </FormAcao>
      )}
      <p className="suave">
        Sem integração com operadora de cartão ou banco: toda cobrança gera uma fatura aqui, e o pagamento é registrado
        à mão quando confirmado.
      </p>
      {assinatura.status === 'ativa' && assinatura.proxima_cobranca && (
        <FormAcao acao={gerarProximaCobranca} rotulo={`Gerar cobrança que começa em ${formatarData(assinatura.proxima_cobranca)}`}>
          <input type="hidden" name="assinatura_id" value={assinatura.id} />
        </FormAcao>
      )}

      <h3>Faturas</h3>
      {faturas.length === 0 ? (
        <p>Nenhuma fatura desta assinatura.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Vencimento</th>
                <th>Período</th>
                <th>Valor</th>
                <th>Situação</th>
                <th>Pagamento</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {faturas.map((f) => (
                <tr key={f.id}>
                  <td>{formatarData(f.vencimento)}</td>
                  <td>{f.periodo_inicio ? `${formatarData(f.periodo_inicio)} a ${formatarData(f.periodo_fim)}` : 'avulsa'}</td>
                  <td>{formatarReais(f.valor_centavos)}</td>
                  <td>
                    {rotulo(STATUS_FATURA, f.status)}
                    {f.observacao ? <div className="suave">{f.observacao}</div> : null}
                  </td>
                  <td>
                    {f.data_pagamento
                      ? `${formatarData(f.data_pagamento)} · ${f.metodo ? rotulo(METODO_PAGAMENTO, f.metodo) : ''}`
                      : '—'}
                  </td>
                  <td>
                    <AcoesDaFatura faturaId={f.id} status={f.status} hoje={hoje} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {assinatura.status === 'ativa' && (
        <>
          <h3>Nova fatura avulsa</h3>
          <FormAcao acao={criarFatura} rotulo="Criar fatura">
            <input type="hidden" name="assinatura_id" value={assinatura.id} />
            <div className="grade">
              <div>
                <label htmlFor="vencimento">Vencimento</label>
                <input id="vencimento" name="vencimento" type="date" defaultValue={hoje} required />
              </div>
              <div>
                <label htmlFor="valor">Valor (R$)</label>
                <input
                  id="valor"
                  name="valor"
                  inputMode="decimal"
                  defaultValue={valorSugerido !== null ? centavosParaCampo(valorSugerido) : ''}
                  placeholder="deixe vazio para calcular"
                />
              </div>
              <div>
                <label htmlFor="obs-fatura">Observação</label>
                <input id="obs-fatura" name="observacao" maxLength={500} />
              </div>
            </div>
          </FormAcao>
          <p className="suave">
            O valor sugerido é calculado (pentes × preço × entregas do mês, com 10% na 1ª fatura quando
            aplicável). Você pode ajustá-lo.
          </p>
        </>
      )}

      {vigente && (
        <>
          <h2>Trocar plano</h2>
          <FormAcao acao={alterarPlanoAssinatura} rotulo="Trocar plano" linha>
            <input type="hidden" name="assinatura_id" value={assinatura.id} />
            <div>
              <label htmlFor="plano_id">Plano</label>
              <select id="plano_id" name="plano_id" defaultValue={assinatura.plano_id}>
                {planos.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.nome}
                  </option>
                ))}
              </select>
            </div>
          </FormAcao>
        </>
      )}
    </Pagina>
  );
}
