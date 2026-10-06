import Link from 'next/link';
import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { Pagina, SemPermissao } from '../_componentes/pagina';
import { formatarData, hojeEmSaoPaulo } from '@/lib/formatar';
import { SolicitacoesPendentes, type Solicitacao } from './solicitacoes';
import { STATUS_ASSINATURA, rotulo } from '@/lib/rotulos';
import { escaparParaBusca } from '@/lib/validacao';

type Linha = {
  id: string;
  cliente_id: string;
  cliente_nome: string;
  plano_nome: string;
  status: string;
  data_inicio: string;
  proxima_entrega: string | null;
  aguardando_pagamento_desde: string | null;
  bloqueada_desde: string | null;
};

const STATUS = Object.keys(STATUS_ASSINATURA);

export default async function Assinaturas({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string }>;
}) {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const filtros = await searchParams;
  const q = (filtros.q ?? '').trim();
  const status = STATUS.includes(filtros.status ?? '') ? filtros.status! : null;

  const { linhas, pedidos } = await comoUsuario(autorizacao.usuario.usuarioId, async (bd) => ({
    pedidos: await bd.consultar<Solicitacao>(
      `select s.id, s.tipo::text, s.motivo, s.preferencia, pd.nome as plano_destino_nome,
              to_char(s.criado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') as criado_em,
              c.nome as cliente_nome, s.assinatura_id, a.status::text as assinatura_status
         from solicitacoes_assinatura s
         join clientes c on c.id = s.cliente_id
         join assinaturas a on a.id = s.assinatura_id
         left join planos pd on pd.id = s.plano_destino_id
        where s.status = 'pendente'
        order by s.criado_em`,
    ),
    linhas: await bd.consultar<Linha>(
      `select a.id, a.cliente_id, c.nome as cliente_nome, p.nome as plano_nome,
              a.status::text, a.data_inicio::text, a.proxima_entrega::text,
              a.aguardando_pagamento_desde::text, a.bloqueada_desde::text
         from assinaturas a
         join clientes c on c.id = a.cliente_id
         join planos p on p.id = a.plano_id
        where ($1::text is null or c.nome ilike $1)
          and ($2::text is null or a.status::text = $2)
        order by (a.status = 'ativa') desc, a.proxima_entrega nulls last, c.nome
        limit 300`,
      [q ? `%${escaparParaBusca(q)}%` : null, status],
    ),
  }));

  return (
    <Pagina titulo="Assinaturas">
      <h2>Pedidos dos assinantes ({pedidos.length})</h2>
      <SolicitacoesPendentes solicitacoes={pedidos} hoje={hojeEmSaoPaulo()} mostrarCliente />

      <h2>Todas as assinaturas</h2>
      <p className="suave">
        Para criar uma assinatura, abra o cliente em <Link href="/clientes">Clientes</Link>.
      </p>

      <form method="get" className="filtros">
        <div>
          <label htmlFor="q">Cliente</label>
          <input id="q" name="q" defaultValue={q} />
        </div>
        <div>
          <label htmlFor="status">Situação</label>
          <select id="status" name="status" defaultValue={status ?? ''}>
            <option value="">Todas</option>
            {STATUS.map((s) => (
              <option key={s} value={s}>
                {rotulo(STATUS_ASSINATURA, s)}
              </option>
            ))}
          </select>
        </div>
        <button type="submit">Filtrar</button>
        <Link href="/assinaturas">Limpar</Link>
      </form>

      {linhas.length === 0 ? (
        <p>Nenhuma assinatura encontrada.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Cliente</th>
                <th>Plano</th>
                <th>Situação</th>
                <th>Início</th>
                <th>Próxima entrega</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((a) => (
                <tr key={a.id}>
                  <td>
                    <Link href={`/clientes/${a.cliente_id}`}>{a.cliente_nome}</Link>
                  </td>
                  <td>{a.plano_nome}</td>
                  <td>
                    {a.bloqueada_desde
                      ? 'Bloqueada (inadimplência)'
                      : a.aguardando_pagamento_desde
                        ? 'Aguardando 1º pagamento'
                        : rotulo(STATUS_ASSINATURA, a.status)}
                  </td>
                  <td>{formatarData(a.data_inicio)}</td>
                  <td>{a.bloqueada_desde ? 'paradas até o pagamento' : a.aguardando_pagamento_desde ? 'após o pagamento' : formatarData(a.proxima_entrega)}</td>
                  <td>
                    <Link href={`/assinaturas/${a.id}`}>Abrir</Link>
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
