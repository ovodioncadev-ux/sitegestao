import Link from 'next/link';
import { notFound } from 'next/navigation';
import { comoAdmin, comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { FormAcao } from '../../_componentes/form-acao';
import { Pagina, SemPermissao } from '../../_componentes/pagina';
import { CamposCliente, type ValoresCliente } from '../campos-cliente';
import { atualizarCliente, desvincularConta, vincularConta } from '../acoes';
import { criarAssinatura } from '../../assinaturas/acoes';
import { STATUS_ASSINATURA, rotulo } from '@/lib/rotulos';
import { formatarData, hojeEmSaoPaulo } from '@/lib/formatar';
import { uuid } from '@/lib/validacao';

type AssinaturaLinha = {
  id: string;
  status: string;
  data_inicio: string;
  proxima_entrega: string | null;
  plano_nome: string;
};

type ClienteDetalhe = ValoresCliente & {
  id: string;
  codigo_indicacao: string;
  dentro_area_entrega: boolean;
};

export default async function EditarCliente({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  // id que não é uuid vira 404, não erro do Postgres.
  try {
    uuid(id, 'Cliente');
  } catch {
    notFound();
  }

  const { cliente, planos, planosComId, assinaturas, indicacao } = await comoUsuario(autorizacao.usuario.usuarioId, async (bd) => {
    const cliente = await bd.umaLinha<ClienteDetalhe>(
      `select c.id, c.nome, c.email, c.telefone, c.cep, c.endereco, c.numero, c.complemento,
              c.bairro, c.cidade, c.estado, c.status::text, c.pentes_padrao, c.duzias_padrao,
              c.desconto_primeiro_mes_aplicavel, c.codigo_indicacao, c.dentro_area_entrega,
              p.frequencia::text as frequencia
         from clientes c
         left join planos p on p.id = c.plano_id
        where c.id = $1`,
      [id],
    );
    const planos = await bd.consultar<{ frequencia: string; nome: string }>(
      'select frequencia::text, nome from planos where ativo order by intervalo_dias',
    );
    const planosComId = await bd.consultar<{ id: number; nome: string }>(
      'select id, nome from planos where ativo order by intervalo_dias',
    );
    const assinaturas = await bd.consultar<AssinaturaLinha>(
      `select a.id, a.status::text, a.data_inicio::text, a.proxima_entrega::text, p.nome as plano_nome
         from assinaturas a join planos p on p.id = a.plano_id
        where a.cliente_id = $1
        order by a.criado_em desc`,
      [id],
    );
    const indicacao = await bd.umaLinha<{ indicou: string; pendentes: string; aplicados: string; indicado_por_nome: string | null }>(
      `select (select count(*) from clientes i where i.indicado_por = $1) as indicou,
              (select count(*) from bonus_indicacao b where b.indicador_id = $1 and b.status = 'pendente') as pendentes,
              (select count(*) from bonus_indicacao b where b.indicador_id = $1 and b.status = 'aplicado') as aplicados,
              (select ic.nome from clientes c2 join clientes ic on ic.id = c2.indicado_por where c2.id = $1) as indicado_por_nome`,
      [id],
    );
    return { cliente, planos, planosComId, assinaturas, indicacao };
  });

  if (!cliente) notFound();

  // As tabelas de credencial do Better Auth não são alcançáveis pelo papel
  // app_usuario (de propósito). O dono já foi confirmado acima; esta leitura
  // administrativa devolve só o e-mail e a confirmação, nunca hash nem sessão.
  const conta = await comoAdmin((bd) =>
    bd.umaLinha<{ email: string; confirmado: boolean }>(
      `select u.email, u."emailVerified" as confirmado
         from clientes c join "user" u on u.id = c.usuario_id where c.id = $1`,
      [id],
    ),
  );

  const vigente = assinaturas.some((a) => a.status === 'ativa' || a.status === 'pausada');

  return (
    <Pagina titulo={`Cliente: ${cliente.nome}`}>
      <p>
        <Link href="/clientes">← Clientes</Link>
      </p>
      <p className="suave">
        Código {cliente.codigo_indicacao} · {cliente.dentro_area_entrega ? 'dentro' : 'fora'} da área de
        entrega
      </p>
      {indicacao && (Number(indicacao.indicou) > 0 || indicacao.indicado_por_nome) && (
        <p className="suave">
          {indicacao.indicado_por_nome ? `Indicado por ${indicacao.indicado_por_nome}. ` : ''}
          {Number(indicacao.indicou) > 0
            ? `Indicou ${indicacao.indicou} pessoa(s): bônus de indicação ${indicacao.pendentes} a aplicar, ${indicacao.aplicados} já aplicado(s).`
            : ''}
        </p>
      )}

      <p>
        <Link href={`/historico?entidade=clientes&id=${cliente.id}`}>Ver histórico deste cliente</Link>
      </p>

      <h2>Dados do cliente</h2>
      <FormAcao acao={atualizarCliente} rotulo="Salvar alterações">
        <input type="hidden" name="id" value={cliente.id} />
        <CamposCliente planos={planos} valores={cliente} planoTravado={vigente} />
      </FormAcao>

      <h2>Conta de login</h2>
      {conta ? (
        <>
          <p>
            Vinculada a {conta.email} ({conta.confirmado ? 'e-mail confirmado' : 'e-mail NÃO confirmado'}).
          </p>
          <FormAcao acao={desvincularConta} rotulo="Desvincular conta">
            <input type="hidden" name="id" value={cliente.id} />
          </FormAcao>
        </>
      ) : (
        <>
          <p className="suave">
            Sem conta vinculada. O vínculo automático só acontece com o e-mail da conta confirmado; se a pessoa já
            criou a conta, vincule aqui depois de conferir que é ela.
          </p>
          <FormAcao acao={vincularConta} rotulo="Vincular conta" limpar>
            <input type="hidden" name="id" value={cliente.id} />
            <label htmlFor="email_conta">E-mail da conta</label>
            <input id="email_conta" name="email_conta" type="email" required />
          </FormAcao>
        </>
      )}

      <h2>Assinaturas</h2>
      {assinaturas.length === 0 ? (
        <p>Este cliente ainda não tem assinatura.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Plano</th>
                <th>Situação</th>
                <th>Início</th>
                <th>Próxima entrega</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {assinaturas.map((a) => (
                <tr key={a.id}>
                  <td>{a.plano_nome}</td>
                  <td>{rotulo(STATUS_ASSINATURA, a.status)}</td>
                  <td>{formatarData(a.data_inicio)}</td>
                  <td>{formatarData(a.proxima_entrega)}</td>
                  <td>
                    <Link href={`/assinaturas/${a.id}`}>Abrir</Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {!vigente && (
        <>
          <h3>Nova assinatura</h3>
          <FormAcao acao={criarAssinatura} rotulo="Criar assinatura">
            <input type="hidden" name="cliente_id" value={cliente.id} />
            <div className="grade">
              <div>
                <label htmlFor="plano_id">Plano</label>
                <select id="plano_id" name="plano_id" required>
                  {planosComId.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.nome}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor="data_inicio">Início</label>
                <input id="data_inicio" name="data_inicio" type="date" defaultValue={hojeEmSaoPaulo()} />
              </div>
            </div>
          </FormAcao>
          <p className="suave">
            Exige CEP e endereço preenchidos e o CEP dentro da área de entrega.
          </p>
        </>
      )}
    </Pagina>
  );
}
