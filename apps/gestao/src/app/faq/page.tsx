import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { FormAcao } from '../_componentes/form-acao';
import { Aviso, Pagina, SemPermissao } from '../_componentes/pagina';
import { alternarPergunta, criarPergunta, editarPergunta, removerPergunta } from './acoes';

type Item = { id: string; pergunta: string; resposta: string; ordem: number; ativo: boolean };

export default async function Faq() {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const itens = await comoUsuario(autorizacao.usuario.usuarioId, (bd) =>
    bd.consultar<Item>('select id, pergunta, resposta, ordem, ativo from faq_itens order by ordem, id'),
  );

  return (
    <Pagina titulo="Perguntas frequentes do site">
      <Aviso tipo="info">
        Estas perguntas aparecem na seção FAQ do site (até 30 segundos depois de salvar). A pergunta sobre como
        falar no WhatsApp é fixa e usa o número cadastrado no código: não escreva telefone aqui.
      </Aviso>

      <h2>Adicionar pergunta</h2>
      <FormAcao acao={criarPergunta} rotulo="Adicionar pergunta" limpar>
        <div>
          <label htmlFor="nova-pergunta">Pergunta</label>
          <input id="nova-pergunta" name="pergunta" required minLength={5} maxLength={200} />
        </div>
        <div>
          <label htmlFor="nova-resposta">Resposta</label>
          <textarea id="nova-resposta" name="resposta" required minLength={5} maxLength={1000} rows={3} />
        </div>
        <div>
          <label htmlFor="nova-ordem">Ordem (menor aparece primeiro)</label>
          <input id="nova-ordem" name="ordem" type="number" min={0} max={9999} defaultValue={100} />
        </div>
      </FormAcao>

      <h2>Perguntas cadastradas ({itens.length})</h2>
      {itens.length === 0 ? (
        <p>Nenhuma pergunta cadastrada: o site mostra só o contato por WhatsApp.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Pergunta</th>
                <th>Situação</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {itens.map((i) => (
                <tr key={i.id}>
                  <td>
                    <FormAcao acao={editarPergunta} rotulo="Salvar" linha>
                      <input type="hidden" name="id" value={i.id} />
                      <div>
                        <label htmlFor={`p-${i.id}`}>Pergunta</label>
                        <input id={`p-${i.id}`} name="pergunta" defaultValue={i.pergunta} required minLength={5} maxLength={200} />
                      </div>
                      <div>
                        <label htmlFor={`r-${i.id}`}>Resposta</label>
                        <textarea id={`r-${i.id}`} name="resposta" defaultValue={i.resposta} required minLength={5} maxLength={1000} rows={3} />
                      </div>
                      <div>
                        <label htmlFor={`o-${i.id}`}>Ordem</label>
                        <input id={`o-${i.id}`} name="ordem" type="number" min={0} max={9999} defaultValue={i.ordem} />
                      </div>
                    </FormAcao>
                  </td>
                  <td>{i.ativo ? 'Publicada' : 'Oculta'}</td>
                  <td>
                    <FormAcao acao={alternarPergunta} rotulo={i.ativo ? 'Ocultar' : 'Publicar'} linha>
                      <input type="hidden" name="id" value={i.id} />
                      <input type="hidden" name="ativar" value={i.ativo ? 'nao' : 'sim'} />
                    </FormAcao>
                    <FormAcao acao={removerPergunta} rotulo="Remover" linha>
                      <input type="hidden" name="id" value={i.id} />
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
