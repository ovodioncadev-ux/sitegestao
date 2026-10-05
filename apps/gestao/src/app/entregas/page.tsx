import Link from 'next/link';
import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { Pagina, SemPermissao } from '../_componentes/pagina';
import { AcoesDaEntrega } from './acoes-entrega';
import { formatarCep, formatarData, formatarTelefone, hojeEmSaoPaulo } from '@/lib/formatar';
import { STATUS_ENTREGA, rotulo } from '@/lib/rotulos';
import { dataOpcional } from '@/lib/validacao';

type Linha = {
  id: string;
  data_prevista: string;
  status: string;
  observacao: string | null;
  pentes: number;
  duzias: number;
  assinatura_id: string;
  cliente_id: string;
  nome: string;
  telefone: string | null;
  endereco: string | null;
  numero: string | null;
  complemento: string | null;
  bairro: string | null;
  cidade: string | null;
  estado: string | null;
  cep: string | null;
  plano_nome: string;
  horario_previsto: string | null;
  ovos_a_repor: number;
};

type Busca = { visao?: string; data?: string; status?: string };

const VISOES = ['dia', 'pendentes', 'atrasadas'] as const;
const STATUS = Object.keys(STATUS_ENTREGA);

function enderecoCompleto(l: Linha): string {
  const rua = [l.endereco, l.numero].filter(Boolean).join(', ');
  const local = [l.complemento, l.bairro].filter(Boolean).join(' · ');
  const cidade = [l.cidade, l.estado].filter(Boolean).join('/');
  return [rua, local, cidade, l.cep ? formatarCep(l.cep) : null].filter(Boolean).join(' — ') || '—';
}

export default async function Entregas({ searchParams }: { searchParams: Promise<Busca> }) {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const filtros = await searchParams;
  const hoje = hojeEmSaoPaulo();
  const visao = (VISOES as readonly string[]).includes(filtros.visao ?? '') ? filtros.visao! : 'dia';
  let data = hoje;
  try {
    data = dataOpcional(filtros.data ?? '', 'Data') ?? hoje;
  } catch {
    data = hoje;
  }
  const status = STATUS.includes(filtros.status ?? '') ? filtros.status! : null;

  const linhas = await comoUsuario(autorizacao.usuario.usuarioId, (bd) =>
    bd.consultar<Linha>(
      `select e.id, e.data_prevista::text, e.status::text, e.observacao, e.pentes, e.duzias,
              e.assinatura_id, c.id as cliente_id, c.nome, c.telefone, c.endereco, c.numero,
              c.complemento, c.bairro, c.cidade, c.estado, c.cep, p.nome as plano_nome,
              to_char(e.horario_previsto, 'HH24:MI') as horario_previsto,
              coalesce((select sum(r.quantidade_ovos) from reposicoes r
                         where r.entrega_reposicao_id = e.id and r.status = 'pendente'), 0)::int as ovos_a_repor
         from entregas e
         join clientes c    on c.id = e.cliente_id
         join assinaturas a on a.id = e.assinatura_id
         join planos p      on p.id = a.plano_id
        where case $1::text
                when 'pendentes' then e.status = 'pendente'
                when 'atrasadas' then e.status = 'pendente' and e.data_prevista < $2::date
                else e.data_prevista = $2::date
              end
          and ($3::text is null or e.status::text = $3)
        order by e.data_prevista, c.bairro nulls last, e.horario_previsto nulls last, c.nome
        limit 500`,
      [visao, visao === 'atrasadas' ? hoje : data, status],
    ),
  );

  const conta = (s: string) => linhas.filter((l) => l.status === s).length;
  const titulo =
    visao === 'pendentes'
      ? 'Entregas pendentes (todas as datas)'
      : visao === 'atrasadas'
        ? 'Entregas atrasadas'
        : data === hoje
          ? 'Entregas de hoje'
          : `Entregas de ${formatarData(data)}`;

  return (
    <Pagina titulo={titulo}>
      <p>
        <Link href="/entregas">Hoje</Link> · <Link href="/entregas?visao=pendentes">Pendentes</Link> ·{' '}
        <Link href="/entregas?visao=atrasadas">Atrasadas</Link>
      </p>

      <form method="get" className="filtros">
        <input type="hidden" name="visao" value="dia" />
        <div>
          <label htmlFor="data">Data</label>
          <input id="data" name="data" type="date" defaultValue={data} />
        </div>
        <div>
          <label htmlFor="status">Situação</label>
          <select id="status" name="status" defaultValue={status ?? ''}>
            <option value="">Todas</option>
            {STATUS.map((s) => (
              <option key={s} value={s}>
                {rotulo(STATUS_ENTREGA, s)}
              </option>
            ))}
          </select>
        </div>
        <button type="submit">Ver</button>
      </form>

      <p className="suave">
        {linhas.length} entrega{linhas.length === 1 ? '' : 's'} · {conta('pendente')} pendente(s) ·{' '}
        {conta('entregue')} entregue(s) · {conta('nao_entregue')} não entregue(s)
        {linhas.length === 500 ? ' (mostrando as 500 primeiras)' : ''}
      </p>

      {linhas.length === 0 ? (
        <p>Nenhuma entrega encontrada.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Data</th>
                <th>Horário</th>
                <th>Bairro</th>
                <th>Cliente</th>
                <th>Endereço</th>
                <th>Telefone</th>
                <th>Plano</th>
                <th>Quantidade</th>
                <th>Situação</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((l) => (
                <tr key={l.id}>
                  <td>{formatarData(l.data_prevista)}</td>
                  <td>{l.horario_previsto ?? '—'}</td>
                  <td>{l.bairro ?? '—'}</td>
                  <td>
                    <Link href={`/clientes/${l.cliente_id}`}>{l.nome}</Link>
                  </td>
                  <td>{enderecoCompleto(l)}</td>
                  <td>{formatarTelefone(l.telefone)}</td>
                  <td>
                    <Link href={`/assinaturas/${l.assinatura_id}`}>{l.plano_nome}</Link>
                  </td>
                  <td>
                    {l.pentes} pente{l.pentes === 1 ? '' : 's'}
                    {l.duzias > 0 ? ` + ${l.duzias} dúzia${l.duzias === 1 ? '' : 's'}` : ''}
                    {l.ovos_a_repor > 0 ? <div className="msg-info">+ repor {l.ovos_a_repor} ovo(s) (defeito, sem custo)</div> : null}
                  </td>
                  <td>
                    {rotulo(STATUS_ENTREGA, l.status)}
                    {l.observacao ? <div className="suave">{l.observacao}</div> : null}
                  </td>
                  <td>
                    <AcoesDaEntrega
                      entregaId={l.id}
                      status={l.status}
                      observacao={l.observacao}
                      horario={l.horario_previsto}
                      hoje={hoje}
                    />
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
