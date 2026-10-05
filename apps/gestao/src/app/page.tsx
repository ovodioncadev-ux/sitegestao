import Link from 'next/link';
import { redirect } from 'next/navigation';
import { comoUsuario } from '@ovo/database';
import { usuarioAtual } from '@ovo/database/papel';
import { Pagina, SemPermissao } from './_componentes/pagina';
import { FormAcao } from './_componentes/form-acao';
import { rodarRotinaDiaria } from './acoes-painel';
import { formatarReais, hojeEmSaoPaulo } from '@/lib/formatar';

type Plano = {
  nome: string;
  frete_centavos: number;
  desconto_primeiro_mes_pct: string;
  freshness_max_dias: number;
  intervalo_dias: number;
};

export default async function PainelInicial() {
  const usuario = await usuarioAtual();
  if (!usuario) redirect('/entrar');

  // Este painel é do dono. Um assinante que chegue aqui não vê nada de negócio.
  if (usuario.papel !== 'dono') {
    return <SemPermissao mensagem="Você não tem permissão para realizar esta ação." />;
  }

  const { planos, totalClientes, hoje, pendencias } = await comoUsuario(usuario.usuarioId, async (bd) => {
    const planos = await bd.consultar<Plano>(
      `select nome, frete_centavos, desconto_primeiro_mes_pct, freshness_max_dias, intervalo_dias
         from planos where ativo order by intervalo_dias`,
    );
    const linha = await bd.umaLinha<{ total: string }>('select count(*) as total from clientes');
    const h = await bd.umaLinha<{ pendentes: string; total: string; atrasadas: string }>(
      `select count(*) filter (where status = 'pendente') as pendentes,
              count(*) as total,
              (select count(*) from entregas where status = 'pendente' and data_prevista < $1::date) as atrasadas
         from entregas where data_prevista = $1::date`,
      [hojeEmSaoPaulo()],
    );
    const p = await bd.umaLinha<{ pedidos: string; reposicoes: string; faixas: string; cobrar: string; devendo: string }>(
      `select (select count(*) from solicitacoes_assinatura where status = 'pendente') as pedidos,
              (select count(*) from reposicoes where status = 'pendente') as reposicoes,
              (select count(*) from faixas_cep_atendidas where ativo) as faixas,
              (select count(*) from assinaturas where status = 'ativa' and proxima_cobranca <= $1::date) as cobrar,
              (select count(*) from faturas where status in ('pendente', 'atrasada') and vencimento < $1::date) as devendo`,
      [hojeEmSaoPaulo()],
    );
    return {
      pendencias: {
        pedidos: Number(p?.pedidos ?? 0),
        reposicoes: Number(p?.reposicoes ?? 0),
        faixas: Number(p?.faixas ?? 0),
        cobrar: Number(p?.cobrar ?? 0),
        devendo: Number(p?.devendo ?? 0),
      },
      planos,
      totalClientes: Number(linha?.total ?? 0),
      hoje: {
        pendentes: Number(h?.pendentes ?? 0),
        total: Number(h?.total ?? 0),
        atrasadas: Number(h?.atrasadas ?? 0),
      },
    };
  });

  return (
    <Pagina titulo="Painel do dono">
      <p>
        <strong>{totalClientes}</strong> cliente{totalClientes === 1 ? '' : 's'} cadastrado
        {totalClientes === 1 ? '' : 's'}. <Link href="/clientes">Ver clientes</Link>
      </p>

      {pendencias.faixas === 0 && (
        <p className="msg-erro" role="alert">
          Nenhuma faixa de CEP ativa: nenhum cliente está “dentro da área” e ninguém consegue assinar.{' '}
          <Link href="/area-de-entrega">Cadastrar área de entrega</Link>
        </p>
      )}

      <h2>Pendências</h2>
      <ul>
        <li>
          <Link href="/assinaturas">{pendencias.pedidos} pedido(s) de assinante</Link> aguardando resposta
        </li>
        <li>{pendencias.reposicoes} reposição(ões) de defeito a entregar</li>
        <li>{pendencias.cobrar} assinatura(s) com cobrança do período a gerar</li>
        <li>
          <Link href="/faturas">{pendencias.devendo} fatura(s) vencida(s)</Link> sem pagamento
        </li>
      </ul>

      <h2>Rotina diária</h2>
      <p className="suave">
        Reativa pausas cujo retorno chegou, gera as cobranças do período e marca faturas atrasadas. Pode ser disparada
        por agendador externo (POST /api/rotina com CRON_SECRET) ou aqui. Rodar mais de uma vez não duplica nada.
      </p>
      <FormAcao acao={rodarRotinaDiaria} rotulo="Rodar rotina agora" />

      <h2>Hoje</h2>
      <p>
        <strong>{hoje.pendentes}</strong> de {hoje.total} entrega{hoje.total === 1 ? '' : 's'} de hoje
        pendente{hoje.pendentes === 1 ? '' : 's'}.{' '}
        <Link href="/entregas">Ver entregas de hoje</Link>
        {hoje.atrasadas > 0 && (
          <>
            {' '}
            · <Link href="/entregas?visao=atrasadas">{hoje.atrasadas} atrasada(s)</Link>
          </>
        )}
      </p>

      <h2>Planos</h2>
      <div className="tabela-rolavel">
        <table>
          <thead>
            <tr>
              <th>Plano</th>
              <th>Intervalo</th>
              <th>Frete</th>
              <th>Desconto 1º mês</th>
              <th>Frescor</th>
            </tr>
          </thead>
          <tbody>
            {planos.map((p) => (
              <tr key={p.nome}>
                <td>{p.nome}</td>
                <td>{p.intervalo_dias} dias</td>
                <td>{formatarReais(p.frete_centavos)}</td>
                <td>{Number(p.desconto_primeiro_mes_pct)}%</td>
                <td>até {p.freshness_max_dias} dias</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Pagina>
  );
}
