import Link from 'next/link';
import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { Pagina, SemPermissao } from '../_componentes/pagina';
import { calcularMudancas } from '@/lib/diff';
import { dataOpcional } from '@/lib/validacao';

type Linha = {
  id: string;
  quando: string;
  quem: string | null;
  acao: string;
  entidade: string;
  entidade_id: string;
  motivo: string | null;
  dados_anteriores: Record<string, unknown> | null;
  dados_novos: Record<string, unknown> | null;
};

const ENTIDADES: Record<string, string> = {
  clientes: 'Cliente',
  assinaturas: 'Assinatura',
  entregas: 'Entrega',
  faturas: 'Fatura',
  planos: 'Plano',
  config_negocio: 'Configuração',
  faixas_cep_atendidas: 'Faixa de CEP',
  solicitacoes_assinatura: 'Solicitação',
  reposicoes: 'Reposição',
};

const NOME_ACAO: Record<string, string> = {
  cliente_criado: 'Cliente criado',
  cliente_alterado: 'Cliente alterado',
  conta_vinculada: 'Conta de login vinculada',
  conta_desvinculada: 'Conta de login desvinculada',
  assinatura_criada: 'Assinatura criada',
  assinatura_alterada: 'Assinatura alterada',
  assinatura_pausada: 'Assinatura pausada',
  assinatura_cancelada: 'Assinatura cancelada',
  assinatura_reativada: 'Assinatura reativada',
  assinatura_encerrada: 'Assinatura encerrada',
  entrega_criada: 'Entrega criada',
  entrega_alterada: 'Entrega alterada',
  entrega_marcada_entregue: 'Entrega marcada como entregue',
  entrega_marcada_nao_entregue: 'Entrega marcada como não entregue',
  entrega_marcada_cancelada: 'Entrega cancelada',
  fatura_criada: 'Fatura criada',
  fatura_alterada: 'Fatura alterada',
  fatura_atrasada: 'Fatura marcada como atrasada',
  pagamento_registrado: 'Pagamento registrado',
  fatura_cancelada: 'Fatura cancelada',
  configuracao_alterada: 'Configuração alterada',
  plano_alterado: 'Plano alterado',
  faixa_criada: 'Faixa de CEP criada',
  faixa_alterada: 'Faixa de CEP alterada',
  faixa_removida: 'Faixa de CEP removida',
  solicitacao_criada: 'Solicitação do assinante',
  solicitacao_alterada: 'Solicitação tratada',
  solicitacoes_assinatura_insert: 'Solicitação do assinante',
  solicitacao_atendida: 'Solicitação atendida',
  solicitacao_recusada: 'Solicitação recusada',
  plano_da_assinatura_alterado: 'Plano da assinatura alterado',
  forma_cobranca_alterada: 'Forma de cobrança alterada',
  defeito_registrado: 'Defeito registrado',
  reposicao_realizada: 'Reposição realizada',
  reposicao_cancelada: 'Reposição cancelada',
  reposicao_alterada: 'Reposição alterada',
};

function ligacao(l: Linha): string | null {
  const dados = l.dados_novos ?? l.dados_anteriores ?? {};
  if (l.entidade === 'clientes') return `/clientes/${l.entidade_id}`;
  if (l.entidade === 'assinaturas') return `/assinaturas/${l.entidade_id}`;
  const assinatura = dados['assinatura_id'];
  if ((l.entidade === 'entregas' || l.entidade === 'faturas' || l.entidade === 'reposicoes' || l.entidade === 'solicitacoes_assinatura') && typeof assinatura === 'string') {
    return `/assinaturas/${assinatura}`;
  }
  return null;
}

type Busca = { entidade?: string; id?: string; de?: string; ate?: string };

export default async function Historico({ searchParams }: { searchParams: Promise<Busca> }) {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const filtros = await searchParams;
  const entidade = filtros.entidade && filtros.entidade in ENTIDADES ? filtros.entidade : null;
  const entidadeId = (filtros.id ?? '').trim() || null;
  const seguro = (v: string | undefined) => {
    try {
      return dataOpcional(v ?? '', 'Data');
    } catch {
      return null;
    }
  };
  const de = seguro(filtros.de);
  const ate = seguro(filtros.ate);

  const linhas = await comoUsuario(autorizacao.usuario.usuarioId, (bd) =>
    bd.consultar<Linha>(
      `select a.id::text,
              to_char(a.criado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI:SS') as quando,
              p.nome as quem, a.acao, a.entidade, a.entidade_id, a.motivo,
              a.dados_anteriores, a.dados_novos
         from auditoria a
         left join perfis p on p.id = a.usuario_id
        where ($1::text is null or a.entidade = $1)
          and ($2::text is null or a.entidade_id = $2)
          and ($3::date is null or (a.criado_em at time zone 'America/Sao_Paulo')::date >= $3::date)
          and ($4::date is null or (a.criado_em at time zone 'America/Sao_Paulo')::date <= $4::date)
        order by a.id desc
        limit 200`,
      [entidade, entidadeId, de, ate],
    ),
  );

  return (
    <Pagina titulo="Histórico de alterações">
      <p className="suave">Quem alterou, quando, o que estava antes e o que ficou depois. Não é possível editar nem apagar.</p>

      <form method="get" className="filtros">
        <div>
          <label htmlFor="entidade">Tipo</label>
          <select id="entidade" name="entidade" defaultValue={entidade ?? ''}>
            <option value="">Todos</option>
            {Object.entries(ENTIDADES).map(([valor, texto]) => (
              <option key={valor} value={valor}>
                {texto}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="id">Id do registro</label>
          <input id="id" name="id" defaultValue={entidadeId ?? ''} />
        </div>
        <div>
          <label htmlFor="de">De</label>
          <input id="de" name="de" type="date" defaultValue={de ?? ''} />
        </div>
        <div>
          <label htmlFor="ate">Até</label>
          <input id="ate" name="ate" type="date" defaultValue={ate ?? ''} />
        </div>
        <button type="submit">Filtrar</button>
        <Link href="/historico">Limpar</Link>
      </form>

      <p className="suave">
        {linhas.length} registro{linhas.length === 1 ? '' : 's'}
        {linhas.length === 200 ? ' (mostrando os 200 mais recentes)' : ''}
      </p>

      {linhas.length === 0 ? (
        <p>Nada encontrado.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Quando</th>
                <th>Quem</th>
                <th>O quê</th>
                <th>Mudanças (antes → depois)</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((l) => {
                const mudancas = calcularMudancas(l.dados_anteriores, l.dados_novos);
                const destino = ligacao(l);
                return (
                  <tr key={l.id}>
                    <td>{l.quando}</td>
                    <td>{l.quem ?? 'Sistema'}</td>
                    <td>
                      {NOME_ACAO[l.acao] ?? l.acao}
                      <div className="suave">
                        {ENTIDADES[l.entidade] ?? l.entidade}{' '}
                        {destino ? <Link href={destino}>abrir</Link> : null}
                      </div>
                      {l.motivo ? <div>Motivo: {l.motivo}</div> : null}
                    </td>
                    <td>
                      {mudancas.length === 0 ? (
                        <span className="suave">—</span>
                      ) : (
                        <ul>
                          {mudancas.map((m) => (
                            <li key={m.campo}>
                              <strong>{m.campo}:</strong>{' '}
                              {l.dados_anteriores === null ? m.depois : `${m.antes} → ${m.depois}`}
                            </li>
                          ))}
                        </ul>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </Pagina>
  );
}
