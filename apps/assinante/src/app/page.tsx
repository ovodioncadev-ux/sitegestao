import Link from 'next/link';
import { comoUsuario } from '@ovo/database';
import { buscarCliente, exigirSessao } from '@/lib/assinante';
import { formatarData, formatarReais, WHATSAPP_URL } from '@/lib/formatar';
import { pagamentoOnlineAtivo } from '@/lib/pagamento/provedor';
import { Pagina } from './_componentes/pagina';
import { FormAcao } from './_componentes/form-acao';
import { solicitarAlteracao } from './acoes';
import { pagarFatura } from './pagamento/acoes';

// Dado de cliente nunca é cacheado nem compartilhado entre pessoas.
export const dynamic = 'force-dynamic';

const STATUS_ASSINATURA: Record<string, string> = {
  ativa: 'Ativa',
  pausada: 'Pausada',
  cancelada: 'Cancelada',
  encerrada: 'Encerrada',
};
const STATUS_ENTREGA: Record<string, string> = {
  pendente: 'Agendada',
  entregue: 'Entregue',
  nao_entregue: 'Não entregue',
  cancelada: 'Cancelada',
};
const STATUS_FATURA: Record<string, string> = {
  pendente: 'Em aberto',
  paga: 'Paga',
  atrasada: 'Atrasada',
  cancelada: 'Cancelada',
};

type Assinatura = {
  id: string;
  status: string;
  data_inicio: string;
  proxima_entrega: string | null;
  plano_nome: string;
  freshness_max_dias: number;
  forma_cobranca: string;
  proxima_cobranca: string | null;
  data_retorno_prevista: string | null;
  /** D8: dia em que passou a aguardar o 1º pagamento (nulo = normal) e prazo para pagar. */
  aguardando_pagamento_desde: string | null;
  pagar_ate: string | null;
  /** D2: entregas paradas por fatura em atraso (nulo = normal). */
  bloqueada_desde: string | null;
};
type Reposicao = { id: string; quantidade_ovos: number; status: string; reposicao: string | null };
type Entrega = { id: string; data_prevista: string; status: string; pentes: number; duzias: number; horario: string | null };
type Fatura = { id: string; valor_centavos: number; vencimento: string; data_pagamento: string | null; status: string };
type Pedido = { tipo: 'pausa' | 'cancelamento' };

export default async function MinhaAssinatura({ searchParams }: { searchParams: Promise<{ nova?: string }> }) {
  const { usuarioId } = await exigirSessao();
  const { nova } = await searchParams;

  // Só colunas que a tela usa (nada de `select *`). A RLS restringe às linhas
  // do próprio cliente; o filtro por cliente_id é a segunda camada.
  const dados = await comoUsuario(usuarioId, async (bd) => {
    const cliente = await buscarCliente(bd, usuarioId);
    if (!cliente) return null;

    const assinatura = await bd.umaLinha<Assinatura>(
      `select a.id, a.status, a.data_inicio::text, a.proxima_entrega::text,
              p.nome as plano_nome, p.freshness_max_dias, a.forma_cobranca::text,
              a.proxima_cobranca::text, a.data_retorno_prevista::text,
              a.aguardando_pagamento_desde::text, a.bloqueada_desde::text,
              (a.aguardando_pagamento_desde + cfg.dias_para_pagar_1a_fatura)::text as pagar_ate
         from assinaturas a
         join planos p on p.id = a.plano_id
         cross join config_negocio cfg
        where a.cliente_id = $1 and cfg.id = 1
        order by (a.status in ('ativa', 'pausada')) desc, a.criado_em desc
        limit 1`,
      [cliente.id],
    );

    const entregas = await bd.consultar<Entrega>(
      `select id, data_prevista::text, status, pentes, duzias, to_char(horario_previsto, 'HH24:MI') as horario
         from entregas
        where cliente_id = $1
        order by data_prevista desc
        limit 12`,
      [cliente.id],
    );

    const faturas = await bd.consultar<Fatura>(
      `select id, valor_centavos, vencimento::text, data_pagamento::text, status
         from faturas
        where cliente_id = $1
        order by vencimento desc
        limit 12`,
      [cliente.id],
    );

    const pedidos = assinatura
      ? await bd.consultar<Pedido>(
          `select tipo from solicitacoes_assinatura
            where assinatura_id = $1 and status = 'pendente'`,
          [assinatura.id],
        )
      : [];

    const reposicoes = await bd.consultar<Reposicao>(
      `select r.id, r.quantidade_ovos, r.status::text, e.data_prevista::text as reposicao
         from reposicoes r left join entregas e on e.id = r.entrega_reposicao_id
        where r.cliente_id = $1 and r.status = 'pendente'
        order by r.criado_em`,
      [cliente.id],
    );

    return { cliente, assinatura, entregas, faturas, pedidos, reposicoes };
  });

  if (!dados) {
    return (
      <Pagina titulo="Minha assinatura">
        <section className="cartao">
          <p>Sua conta ainda não tem um cadastro de assinante. Informe seu endereço e escolha um plano.</p>
          <p>
            <Link className="botao" href="/assinar">
              Escolher um plano
            </Link>
          </p>
          <p className="suave">
            Já é cliente da Ovo di Onça e o seu cadastro foi feito por nós? O vínculo com a conta só é automático
            depois que o e-mail é confirmado; se preferir, fale com a gente.{' '}
            <a href={WHATSAPP_URL} target="_blank" rel="noreferrer">
              WhatsApp
            </a>
          </p>
        </section>
      </Pagina>
    );
  }

  const { cliente, assinatura, entregas, faturas, pedidos, reposicoes } = dados;
  const vigente = assinatura && (assinatura.status === 'ativa' || assinatura.status === 'pausada');
  const pediuPausa = pedidos.some((p) => p.tipo === 'pausa');
  const pediuCancelamento = pedidos.some((p) => p.tipo === 'cancelamento');
  const aguardando = Boolean(assinatura?.aguardando_pagamento_desde) && assinatura?.status === 'ativa';
  const bloqueada = Boolean(assinatura?.bloqueada_desde) && assinatura?.status === 'ativa';
  const pagamentoOnline = pagamentoOnlineAtivo();
  const primeiraEmAberto = faturas.find((f) => f.status === 'pendente' || f.status === 'atrasada');
  // A lista vem da mais nova para a mais antiga: quem destrava é pagar a mais ANTIGA em atraso.
  const maisAntigaEmAtraso = [...faturas].reverse().find((f) => f.status === 'atrasada');

  return (
    <Pagina titulo={`Olá, ${cliente.nome.split(' ')[0]}`}>
      {bloqueada && (
        <section className="cartao" role="alert" aria-labelledby="titulo-bloqueada">
          <h2 id="titulo-bloqueada">Suas entregas estão paradas</h2>
          <p>
            Há fatura em atraso além do prazo de tolerância. Assim que o pagamento for confirmado, as entregas voltam
            automaticamente na próxima quarta disponível.
          </p>
          {pagamentoOnline && maisAntigaEmAtraso ? (
            <FormAcao acao={pagarFatura} rotulo="Pagar agora">
              <input type="hidden" name="fatura" value={maisAntigaEmAtraso.id} />
            </FormAcao>
          ) : (
            <p>
              <a className="botao botao-whatsapp" href={WHATSAPP_URL} target="_blank" rel="noreferrer">
                Enviar comprovante pelo WhatsApp
              </a>
            </p>
          )}
        </section>
      )}
      {aguardando && assinatura && (
        <section className="cartao" role="status" aria-labelledby="titulo-aguardando">
          <h2 id="titulo-aguardando">{nova === '1' ? 'Assinatura criada! Falta o pagamento.' : 'Falta o pagamento da 1ª fatura'}</h2>
          <p>
            Assim que o pagamento for confirmado, agendamos a sua <strong>primeira entrega</strong>
            {assinatura.pagar_ate && (
              <>
                . Pague até <strong>{formatarData(assinatura.pagar_ate)}</strong>; passado o prazo, a assinatura é
                cancelada
              </>
            )}
            .
          </p>
          {pagamentoOnline && primeiraEmAberto ? (
            <FormAcao acao={pagarFatura} rotulo="Pagar agora">
              <input type="hidden" name="fatura" value={primeiraEmAberto.id} />
            </FormAcao>
          ) : (
            <>
              <p className="suave">
                Envie o comprovante do PIX pelo WhatsApp e a Ovo di Onça confirma a cobrança.
              </p>
              <p>
                <a className="botao botao-whatsapp" href={WHATSAPP_URL} target="_blank" rel="noreferrer">
                  Enviar comprovante pelo WhatsApp
                </a>
              </p>
            </>
          )}
        </section>
      )}
      {nova === '1' && assinatura && !aguardando && (
        <section className="cartao" role="status" aria-labelledby="titulo-nova">
          <h2 id="titulo-nova">Assinatura criada!</h2>
          <p>
            Sua primeira entrega está agendada para <strong>{formatarData(assinatura.proxima_entrega)}</strong>.
          </p>
          <p className="suave">
            Como pagar: o pagamento online ainda não está disponível. Envie o comprovante do PIX pelo WhatsApp e a
            Ovo di Onça confirma a cobrança.
          </p>
          <p>
            <a className="botao botao-whatsapp" href={WHATSAPP_URL} target="_blank" rel="noreferrer">
              Enviar comprovante pelo WhatsApp
            </a>
          </p>
        </section>
      )}
      <section className="cartao" aria-labelledby="titulo-assinatura">
        <h2 id="titulo-assinatura">Sua assinatura</h2>
        {!assinatura ? (
          <>
            <p>Você ainda não tem uma assinatura.</p>
            <p>
              <Link className="botao" href="/assinar">
                Escolher um plano
              </Link>
            </p>
          </>
        ) : (
          <dl className="lista-dados">
            <dt>Plano</dt>
            <dd>{assinatura.plano_nome}</dd>
            <dt>Situação</dt>
            <dd>{aguardando ? 'Aguardando o 1º pagamento' : (STATUS_ASSINATURA[assinatura.status] ?? assinatura.status)}</dd>
            <dt>Desde</dt>
            <dd>{formatarData(assinatura.data_inicio)}</dd>
            {assinatura.status === 'ativa' && (
              <>
                <dt>Próxima entrega</dt>
                <dd>{aguardando ? 'Será agendada depois do pagamento' : formatarData(assinatura.proxima_entrega)}</dd>
              </>
            )}
            {assinatura.status === 'pausada' && assinatura.data_retorno_prevista && (
              <>
                <dt>Retorno previsto</dt>
                <dd>{formatarData(assinatura.data_retorno_prevista)}</dd>
              </>
            )}
            <dt>Cobrança</dt>
            <dd>
              {assinatura.forma_cobranca === 'cartao' ? 'Cartão' : 'PIX mensal'}
              {assinatura.status === 'ativa' && assinatura.proxima_cobranca
                ? ` · próxima a partir de ${formatarData(assinatura.proxima_cobranca)}`
                : ''}
            </dd>
            <dt>Frescor</dt>
            <dd>No máximo {assinatura.freshness_max_dias} dias entre a coleta e a entrega</dd>
          </dl>
        )}
      </section>

      {vigente && (
        <section className="cartao" aria-labelledby="titulo-pedidos">
          <h2 id="titulo-pedidos">Pausar ou cancelar</h2>
          <p className="suave">
            Você faz o pedido aqui e a gente responde pelo WhatsApp. Nada muda sozinho.
          </p>

          {assinatura.status === 'ativa' &&
            (pediuPausa ? (
              <p className="msg-info">Seu pedido de pausa está aguardando resposta.</p>
            ) : (
              <FormAcao acao={solicitarAlteracao} rotulo="Pedir pausa" secundario limpar>
                <input type="hidden" name="tipo" value="pausa" />
                <label className="campo">
                  Motivo (opcional)
                  <textarea name="motivo" maxLength={500} rows={2} />
                </label>
              </FormAcao>
            ))}

          {pediuCancelamento ? (
            <p className="msg-info">Seu pedido de cancelamento está aguardando resposta.</p>
          ) : (
            <FormAcao acao={solicitarAlteracao} rotulo="Pedir cancelamento" secundario limpar>
              <input type="hidden" name="tipo" value="cancelamento" />
              <label className="campo">
                Motivo (opcional)
                <textarea name="motivo" maxLength={500} rows={2} />
              </label>
            </FormAcao>
          )}
        </section>
      )}

      <section className="cartao" aria-labelledby="titulo-entregas">
        <h2 id="titulo-entregas">Entregas</h2>
        {entregas.length === 0 ? (
          <p className="suave">Nenhuma entrega ainda.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th scope="col">Data</th>
                <th scope="col">Situação</th>
                <th scope="col">Itens</th>
              </tr>
            </thead>
            <tbody>
              {entregas.map((e) => (
                <tr key={e.id}>
                  <td>
                    {formatarData(e.data_prevista)}
                    {e.horario ? ` · ${e.horario}` : ''}
                  </td>
                  <td>{STATUS_ENTREGA[e.status] ?? e.status}</td>
                  <td>
                    {e.pentes} {e.pentes === 1 ? 'pente' : 'pentes'}
                    {e.duzias > 0 && ` + ${e.duzias} ${e.duzias === 1 ? 'dúzia' : 'dúzias'}`}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      {reposicoes.length > 0 && (
        <section className="cartao" aria-labelledby="titulo-reposicoes">
          <h2 id="titulo-reposicoes">Reposição de ovos com defeito</h2>
          <ul>
            {reposicoes.map((r) => (
              <li key={r.id}>
                {r.quantidade_ovos} ovo(s), sem custo,{' '}
                {r.reposicao ? `na entrega de ${formatarData(r.reposicao)}` : 'na próxima entrega'}.
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="cartao" aria-labelledby="titulo-faturas">
        <h2 id="titulo-faturas">Faturas</h2>
        {faturas.length === 0 ? (
          <p className="suave">Nenhuma fatura ainda.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th scope="col">Vencimento</th>
                <th scope="col">Valor</th>
                <th scope="col">Situação</th>
                {pagamentoOnline && <th scope="col">Pagamento</th>}
              </tr>
            </thead>
            <tbody>
              {faturas.map((f) => (
                <tr key={f.id}>
                  <td>{formatarData(f.vencimento)}</td>
                  <td>{formatarReais(f.valor_centavos)}</td>
                  <td>
                    {STATUS_FATURA[f.status] ?? f.status}
                    {f.data_pagamento && ` em ${formatarData(f.data_pagamento)}`}
                  </td>
                  {pagamentoOnline && (
                    <td>
                      {(f.status === 'pendente' || f.status === 'atrasada') && (
                        <FormAcao acao={pagarFatura} rotulo="Pagar agora">
                          <input type="hidden" name="fatura" value={f.id} />
                        </FormAcao>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <p className="suave">
          {pagamentoOnline
            ? 'O pagamento online é confirmado automaticamente. Dúvidas pelo'
            : 'O pagamento é confirmado por nós'}
          {pagamentoOnline ? '' : assinatura?.forma_cobranca === 'cartao' ? '. Dúvidas pelo' : ': envie o comprovante do PIX pelo'}{' '}
          <a href={WHATSAPP_URL} target="_blank" rel="noreferrer">
            WhatsApp
          </a>
          .
        </p>
      </section>
    </Pagina>
  );
}
