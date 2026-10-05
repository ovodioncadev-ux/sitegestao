import Link from 'next/link';
import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { Pagina, SemPermissao } from '../_componentes/pagina';
import { AcoesDaFatura } from './acoes-fatura';
import { formatarData, formatarReais, hojeEmSaoPaulo } from '@/lib/formatar';
import { METODO_PAGAMENTO, STATUS_FATURA, rotulo } from '@/lib/rotulos';
import { escaparParaBusca } from '@/lib/validacao';

type Linha = {
  id: string;
  cliente_id: string;
  cliente_nome: string;
  assinatura_id: string;
  plano_nome: string;
  valor_centavos: number;
  vencimento: string;
  data_pagamento: string | null;
  status: string;
  metodo: string | null;
  observacao: string | null;
  dias_atraso: number;
  periodo_inicio: string | null;
  periodo_fim: string | null;
  calculo_regra: string | null;
  calculo_entregas: number | null;
  calculo_valor_entrega_centavos: number | null;
  calculo_desconto_centavos: number | null;
  calculo_credito_centavos: number | null;
  calculo_ajuste_centavos: number | null;
};

/** Como o valor foi calculado, lido da própria fatura (nunca do preço atual do plano). */
function descreverCalculo(l: Linha): string {
  const partes = [`${l.calculo_entregas} × ${formatarReais(l.calculo_valor_entrega_centavos)}`];
  if (Number(l.calculo_desconto_centavos) > 0) partes.push(`− ${formatarReais(l.calculo_desconto_centavos)} desconto`);
  if (Number(l.calculo_credito_centavos) > 0) partes.push(`− ${formatarReais(l.calculo_credito_centavos)} crédito`);
  if (Number(l.calculo_ajuste_centavos) !== 0) partes.push(`ajuste ${formatarReais(l.calculo_ajuste_centavos)}`);
  return partes.join(' ');
}

const VISOES = {
  devendo: 'Quem está devendo',
  pagas: 'Quem já pagou',
  todas: 'Todas',
} as const;

const STATUS = Object.keys(STATUS_FATURA);

export default async function Faturas({
  searchParams,
}: {
  searchParams: Promise<{ visao?: string; q?: string; status?: string }>;
}) {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const filtros = await searchParams;
  const visao = (filtros.visao && filtros.visao in VISOES ? filtros.visao : 'devendo') as keyof typeof VISOES;
  const q = (filtros.q ?? '').trim();
  const status = STATUS.includes(filtros.status ?? '') ? filtros.status! : null;
  const hoje = hojeEmSaoPaulo();

  const linhas = await comoUsuario(autorizacao.usuario.usuarioId, (bd) =>
    bd.consultar<Linha>(
      `select f.id, f.cliente_id, c.nome as cliente_nome, f.assinatura_id, coalesce(f.calculo_plano_nome, p.nome) as plano_nome,
              f.valor_centavos, f.vencimento::text, f.data_pagamento::text, f.status::text,
              f.metodo::text, f.observacao, f.periodo_inicio::text, f.periodo_fim::text,
              f.calculo_regra, f.calculo_entregas, f.calculo_valor_entrega_centavos,
              f.calculo_desconto_centavos, f.calculo_credito_centavos, f.calculo_ajuste_centavos,
              case when f.status in ('pendente', 'atrasada') and f.vencimento < $1::date
                   then ($1::date - f.vencimento) else 0 end as dias_atraso
         from faturas f
         join clientes c    on c.id = f.cliente_id
         join assinaturas a on a.id = f.assinatura_id
         join planos p      on p.id = a.plano_id
        where case $2::text
                when 'devendo' then f.status in ('pendente', 'atrasada')
                when 'pagas'   then f.status = 'paga'
                else true
              end
          and ($3::text is null or c.nome ilike $3)
          and ($4::text is null or f.status::text = $4)
        order by case when $2::text = 'pagas' then null else f.vencimento end nulls last,
                 f.data_pagamento desc nulls last, c.nome
        limit 500`,
      [hoje, visao, q ? `%${escaparParaBusca(q)}%` : null, status],
    ),
  );

  const totalCentavos = linhas
    .filter((l) => (visao === 'todas' ? l.status !== 'cancelada' : true))
    .reduce((soma, l) => soma + Number(l.valor_centavos), 0);
  const rotuloTotal =
    visao === 'devendo' ? 'Total em aberto' : visao === 'pagas' ? 'Total recebido' : 'Total (sem canceladas)';

  return (
    <Pagina titulo="Faturas">
      <p>
        {(Object.keys(VISOES) as (keyof typeof VISOES)[]).map((v, i) => (
          <span key={v}>
            {i > 0 ? ' · ' : ''}
            {v === visao ? <strong>{VISOES[v]}</strong> : <Link href={`/faturas?visao=${v}`}>{VISOES[v]}</Link>}
          </span>
        ))}
      </p>

      <form method="get" className="filtros">
        <input type="hidden" name="visao" value={visao} />
        <div>
          <label htmlFor="q">Cliente</label>
          <input id="q" name="q" defaultValue={q} />
        </div>
        {visao === 'todas' && (
          <div>
            <label htmlFor="status">Situação</label>
            <select id="status" name="status" defaultValue={status ?? ''}>
              <option value="">Todas</option>
              {STATUS.map((s) => (
                <option key={s} value={s}>
                  {rotulo(STATUS_FATURA, s)}
                </option>
              ))}
            </select>
          </div>
        )}
        <button type="submit">Filtrar</button>
      </form>

      <p>
        {linhas.length} fatura{linhas.length === 1 ? '' : 's'} · {rotuloTotal}:{' '}
        <strong>{formatarReais(totalCentavos)}</strong>
      </p>

      {linhas.length === 0 ? (
        <p>Nenhuma fatura encontrada.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Cliente</th>
                <th>Valor</th>
                <th>Vencimento</th>
                <th>Período</th>
                <th>Situação</th>
                <th>Pagamento</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((l) => (
                <tr key={l.id}>
                  <td>
                    <Link href={`/clientes/${l.cliente_id}`}>{l.cliente_nome}</Link>
                    <div className="suave">
                      <Link href={`/assinaturas/${l.assinatura_id}`}>{l.plano_nome}</Link>
                    </div>
                  </td>
                  <td>
                    {formatarReais(l.valor_centavos)}
                    {l.calculo_regra ? <div className="suave">{descreverCalculo(l)}</div> : null}
                  </td>
                  <td>{formatarData(l.vencimento)}</td>
                  <td>{l.periodo_inicio ? `${formatarData(l.periodo_inicio)} a ${formatarData(l.periodo_fim)}` : 'avulsa'}</td>
                  <td>
                    {rotulo(STATUS_FATURA, l.status)}
                    {l.dias_atraso > 0 ? <div className="msg-erro">{l.dias_atraso} dia(s) de atraso</div> : null}
                    {l.observacao ? <div className="suave">{l.observacao}</div> : null}
                  </td>
                  <td>
                    {l.data_pagamento
                      ? `${formatarData(l.data_pagamento)} · ${l.metodo ? rotulo(METODO_PAGAMENTO, l.metodo) : ''}`
                      : '—'}
                  </td>
                  <td>
                    <AcoesDaFatura faturaId={l.id} status={l.status} hoje={hoje} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Pagina>
  );
}
