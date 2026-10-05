import Link from 'next/link';
import { comoUsuario } from '@ovo/database';
import { urlWhatsappDe } from '@ovo/config/whatsapp';
import { exigirDono } from '@ovo/database/papel';
import { FormAcao } from '../_componentes/form-acao';
import { Aviso, Pagina, SemPermissao } from '../_componentes/pagina';
import { formatarCep, formatarData, formatarTelefone } from '@/lib/formatar';
import { descartarInteressado, marcarAvisado, removerInteressado } from './acoes';

type Linha = {
  id: string;
  nome: string | null;
  telefone: string | null;
  email: string | null;
  cep: string;
  origem: string;
  status: 'novo' | 'avisado' | 'descartado';
  area_atendida_em: string | null;
  criado_em: string;
};

const VISOES = ['prontos', 'novos', 'todos'] as const;
type Visao = (typeof VISOES)[number];
const ROTULO_STATUS = { novo: 'Aguardando', avisado: 'Avisado', descartado: 'Descartado' } as const;

/** Convite por WhatsApp para quem pediu aviso. O número é do próprio interessado (já normalizado, com DDD). */
function conviteWhatsapp(telefone: string): string {
  const texto = 'Olá! Aqui é da Ovo di Onça. Você pediu para ser avisado: já entregamos no seu CEP! Quer assinar?';
  return urlWhatsappDe(telefone, texto);
}

export default async function Interessados({ searchParams }: { searchParams: Promise<{ visao?: string }> }) {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const { visao: pedida } = await searchParams;
  const visao: Visao = (VISOES as readonly string[]).includes(pedida ?? '') ? (pedida as Visao) : 'prontos';

  const linhas = await comoUsuario(autorizacao.usuario.usuarioId, (bd) =>
    bd.consultar<Linha>(
      `select id, nome, telefone, email, cep, origem, status,
              area_atendida_em::text, criado_em::text
         from interessados
        where ($1 = 'todos')
           or ($1 = 'novos' and status = 'novo')
           or ($1 = 'prontos' and status = 'novo' and area_atendida_em is not null)
        order by (area_atendida_em is null), criado_em desc
        limit 500`,
      [visao],
    ),
  );

  return (
    <Pagina titulo="Interessados fora da área">
      <p className="suave">
        Quem digitou um CEP não atendido e pediu aviso.{' '}
        <strong>Prontos para avisar</strong> são os que já estão numa faixa ativa de{' '}
        <Link href="/area-de-entrega">Área de entrega</Link>.
      </p>
      <Aviso tipo="info">
        São dados pessoais com consentimento. Use só para avisar sobre a entrega e, se a pessoa pedir exclusão,
        use “Remover”: some de vez (não fica no histórico).
      </Aviso>
      <p>
        <Link href="/interessados?visao=prontos">Prontos para avisar</Link> ·{' '}
        <Link href="/interessados?visao=novos">Aguardando</Link> · <Link href="/interessados?visao=todos">Todos</Link>{' '}
        · <a href="/interessados/exportar">Exportar CSV</a>
      </p>

      {linhas.length === 0 ? (
        <p>Nenhum interessado nesta visão.</p>
      ) : (
        <div className="tabela-rolavel">
          <table>
            <thead>
              <tr>
                <th>Pessoa</th>
                <th>CEP</th>
                <th>Pediu em</th>
                <th>Situação</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((l) => (
                <tr key={l.id}>
                  <td>
                    {l.nome ?? 'Sem nome'}
                    <br />
                    {l.telefone && <>{formatarTelefone(l.telefone)} </>}
                    {l.email && <>{l.email}</>}
                  </td>
                  <td>{formatarCep(l.cep)}</td>
                  <td>{formatarData(l.criado_em)}</td>
                  <td>
                    {ROTULO_STATUS[l.status]}
                    {l.status === 'novo' && l.area_atendida_em && <> · área já atendida</>}
                  </td>
                  <td>
                    {l.telefone && (
                      <p>
                        <a href={conviteWhatsapp(l.telefone)} target="_blank" rel="noreferrer">
                          Avisar pelo WhatsApp
                        </a>
                      </p>
                    )}
                    {l.status === 'novo' && (
                      <FormAcao acao={marcarAvisado} rotulo="Marcar como avisado" linha>
                        <input type="hidden" name="id" value={l.id} />
                      </FormAcao>
                    )}
                    {l.status === 'novo' && (
                      <FormAcao acao={descartarInteressado} rotulo="Descartar" linha>
                        <input type="hidden" name="id" value={l.id} />
                      </FormAcao>
                    )}
                    <FormAcao
                      acao={removerInteressado}
                      rotulo="Remover de vez"
                      linha
                      perigo
                      confirmar="Remover estes dados de vez? Não há como desfazer."
                    >
                      <input type="hidden" name="id" value={l.id} />
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
