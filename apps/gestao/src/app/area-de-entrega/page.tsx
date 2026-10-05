import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { FormAcao } from '../_componentes/form-acao';
import { Aviso, Pagina, SemPermissao } from '../_componentes/pagina';
import { formatarCep } from '@/lib/formatar';
import { alternarFaixa, criarFaixa, editarFaixa, removerFaixa } from './acoes';

type Faixa = {
  id: number;
  cep_inicio: string;
  cep_fim: string;
  bairro: string | null;
  ativo: boolean;
};

export default async function AreaDeEntrega() {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const { faixas, dentro, fora } = await comoUsuario(autorizacao.usuario.usuarioId, async (bd) => {
    const faixas = await bd.consultar<Faixa>(
      'select id, cep_inicio, cep_fim, bairro, ativo from faixas_cep_atendidas order by cep_inicio, id',
    );
    const contagem = await bd.umaLinha<{ dentro: string; fora: string }>(
      `select count(*) filter (where dentro_area_entrega) as dentro,
              count(*) filter (where not dentro_area_entrega) as fora
         from clientes`,
    );
    return { faixas, dentro: Number(contagem?.dentro ?? 0), fora: Number(contagem?.fora ?? 0) };
  });

  return (
    <Pagina titulo="Área de entrega">
      <p>
        Clientes dentro da área: <strong>{dentro}</strong> · fora da área (ou sem CEP):{' '}
        <strong>{fora}</strong>
      </p>
      {faixas.filter((f) => f.ativo).length === 0 && (
        <Aviso tipo="info">
          Nenhuma faixa ativa: enquanto for assim, todo cliente fica “fora da área” e não é possível
          criar assinatura. Cadastre ao menos uma faixa de CEP.
        </Aviso>
      )}

      <h2>Adicionar faixa</h2>
      <FormAcao acao={criarFaixa} rotulo="Adicionar faixa" limpar>
        <div className="grade">
          <div>
            <label htmlFor="novo-inicio">CEP inicial</label>
            <input id="novo-inicio" name="cep_inicio" required placeholder="30110-000" />
          </div>
          <div>
            <label htmlFor="novo-fim">CEP final</label>
            <input id="novo-fim" name="cep_fim" required placeholder="30190-999" />
          </div>
          <div>
            <label htmlFor="novo-bairro">Bairro / observação</label>
            <input id="novo-bairro" name="bairro" maxLength={100} />
          </div>
        </div>
      </FormAcao>

      <h2>Faixas cadastradas ({faixas.length})</h2>
      {faixas.length === 0 ? (
        <p>Nenhuma faixa cadastrada.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Faixa</th>
                <th>Situação</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {faixas.map((f) => (
                <tr key={f.id}>
                  <td>
                    <FormAcao acao={editarFaixa} rotulo="Salvar" linha>
                      <input type="hidden" name="id" value={f.id} />
                      <div>
                        <label htmlFor={`i-${f.id}`}>De</label>
                        <input id={`i-${f.id}`} name="cep_inicio" defaultValue={formatarCep(f.cep_inicio)} required />
                      </div>
                      <div>
                        <label htmlFor={`f-${f.id}`}>Até</label>
                        <input id={`f-${f.id}`} name="cep_fim" defaultValue={formatarCep(f.cep_fim)} required />
                      </div>
                      <div>
                        <label htmlFor={`b-${f.id}`}>Bairro</label>
                        <input id={`b-${f.id}`} name="bairro" defaultValue={f.bairro ?? ''} maxLength={100} />
                      </div>
                    </FormAcao>
                  </td>
                  <td>{f.ativo ? 'Ativa' : 'Desativada'}</td>
                  <td>
                    <FormAcao acao={alternarFaixa} rotulo={f.ativo ? 'Desativar' : 'Ativar'} linha>
                      <input type="hidden" name="id" value={f.id} />
                      <input type="hidden" name="ativar" value={f.ativo ? 'nao' : 'sim'} />
                    </FormAcao>
                    <FormAcao acao={removerFaixa} rotulo="Remover" linha>
                      <input type="hidden" name="id" value={f.id} />
                    </FormAcao>
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
