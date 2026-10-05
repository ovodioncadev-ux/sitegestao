import Link from 'next/link';
import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { Pagina, SemPermissao } from '../_componentes/pagina';
import { CHAVES_STATUS_CLIENTE, STATUS_CLIENTE, rotulo } from '@/lib/rotulos';
import { formatarTelefone } from '@/lib/formatar';
import { escaparParaBusca } from '@/lib/validacao';

type ClienteLinha = {
  id: string;
  nome: string;
  email: string | null;
  telefone: string | null;
  status: string;
  codigo_indicacao: string;
  dentro_area_entrega: boolean;
  bairro: string | null;
  plano_nome: string | null;
};

type Filtros = { q?: string; status?: string; plano?: string };

const LIMITE = 200;

export default async function Clientes({ searchParams }: { searchParams: Promise<Filtros> }) {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const filtros = await searchParams;
  const q = (filtros.q ?? '').trim();
  const digitos = q.replace(/\D/g, '');
  const status = CHAVES_STATUS_CLIENTE.includes(filtros.status as never) ? filtros.status! : null;

  const { clientes, planos } = await comoUsuario(autorizacao.usuario.usuarioId, async (bd) => {
    const planos = await bd.consultar<{ frequencia: string; nome: string }>(
      'select frequencia::text, nome from planos order by intervalo_dias',
    );
    const plano = planos.some((p) => p.frequencia === filtros.plano) ? filtros.plano! : null;

    // A busca vale como TEXTO: %, _ e \ digitados são escapados, não são coringa.
    const clientes = await bd.consultar<ClienteLinha>(
      `select c.id, c.nome, c.email, c.telefone, c.status::text, c.codigo_indicacao,
              c.dentro_area_entrega, c.bairro, p.nome as plano_nome
         from clientes c
         left join planos p on p.id = c.plano_id
        where ($1::text is null
               or c.nome ilike $1 or c.email ilike $1 or c.codigo_indicacao ilike $1
               or c.telefone ilike $2)
          and ($3::text is null or c.status::text = $3)
          and ($4::text is null or p.frequencia::text = $4)
        order by c.criado_em desc
        limit ${LIMITE}`,
      [q ? `%${escaparParaBusca(q)}%` : null, digitos ? `%${digitos}%` : null, status, plano],
    );
    return { clientes, planos };
  });

  return (
    <Pagina titulo="Clientes">
      <p>
        <Link href="/clientes/novo">+ Novo cliente</Link>
      </p>

      <form method="get" className="filtros">
        <div>
          <label htmlFor="q">Buscar (nome, e-mail, telefone ou código)</label>
          <input id="q" name="q" defaultValue={q} />
        </div>
        <div>
          <label htmlFor="status">Status</label>
          <select id="status" name="status" defaultValue={status ?? ''}>
            <option value="">Todos</option>
            {CHAVES_STATUS_CLIENTE.map((chave) => (
              <option key={chave} value={chave}>
                {STATUS_CLIENTE[chave]}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="plano">Plano</label>
          <select id="plano" name="plano" defaultValue={filtros.plano ?? ''}>
            <option value="">Todos</option>
            {planos.map((p) => (
              <option key={p.frequencia} value={p.frequencia}>
                {p.nome}
              </option>
            ))}
          </select>
        </div>
        <button type="submit">Filtrar</button>
        <Link href="/clientes">Limpar</Link>
      </form>

      <p className="suave">
        {clientes.length} cliente{clientes.length === 1 ? '' : 's'}
        {clientes.length === LIMITE ? ` (mostrando os ${LIMITE} mais recentes — refine a busca)` : ''}
      </p>

      {clientes.length === 0 ? (
        <p>Nenhum cliente encontrado.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Nome</th>
                <th>Contato</th>
                <th>Código</th>
                <th>Plano</th>
                <th>Status</th>
                <th>Área</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {clientes.map((c) => (
                <tr key={c.id}>
                  <td>
                    {c.nome}
                    {c.bairro ? <span className="suave"> · {c.bairro}</span> : null}
                  </td>
                  <td>
                    {c.email ?? '—'}
                    <br />
                    <span className="suave">{formatarTelefone(c.telefone)}</span>
                  </td>
                  <td>{c.codigo_indicacao}</td>
                  <td>{c.plano_nome ?? '—'}</td>
                  <td>{rotulo(STATUS_CLIENTE, c.status)}</td>
                  <td>{c.dentro_area_entrega ? 'Dentro' : 'Fora'}</td>
                  <td>
                    <Link href={`/clientes/${c.id}`}>Abrir</Link>
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
