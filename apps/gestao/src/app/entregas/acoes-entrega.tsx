import { FormAcao } from '../_componentes/form-acao';
import { definirHorarioEntrega, marcarEntrega, registrarDefeito, salvarObservacaoEntrega } from './acoes';

/** Próxima quarta-feira depois de `iso` (AAAA-MM-DD), como sugestão de reagendamento. */
function proximaQuartaDepoisDe(iso: string): string {
  const d = new Date(`${iso}T00:00:00Z`);
  const dias = ((3 - d.getUTCDay() + 7) % 7) || 7;
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

/**
 * Ações de uma entrega. Pendente: entregue / não entregue (com nova data) /
 * cancelar. Qualquer situação: observação. Formulários dentro de <details>
 * para a tabela continuar legível.
 */
export function AcoesDaEntrega({
  entregaId,
  status,
  observacao,
  horario = null,
  hoje,
}: {
  entregaId: string;
  status: string;
  observacao: string | null;
  horario?: string | null;
  hoje: string;
}) {
  return (
    <div>
      {status === 'pendente' && (
        <>
          <details>
            <summary>Marcar como entregue</summary>
            <FormAcao acao={marcarEntrega} rotulo="Confirmar entrega">
              <input type="hidden" name="entrega_id" value={entregaId} />
              <input type="hidden" name="situacao" value="entregue" />
              <label htmlFor={`obs-e-${entregaId}`}>Observação (opcional)</label>
              <input id={`obs-e-${entregaId}`} name="observacao" maxLength={500} />
            </FormAcao>
          </details>

          <details>
            <summary>Marcar como não entregue</summary>
            <FormAcao acao={marcarEntrega} rotulo="Confirmar não entregue">
              <input type="hidden" name="entrega_id" value={entregaId} />
              <input type="hidden" name="situacao" value="nao_entregue" />
              <label htmlFor={`obs-n-${entregaId}`}>Motivo / observação</label>
              <input id={`obs-n-${entregaId}`} name="observacao" maxLength={500} />
              <label htmlFor={`rea-${entregaId}`}>Reagendar para (deixe vazio para não reagendar)</label>
              <input
                id={`rea-${entregaId}`}
                name="reagendar"
                type="date"
                defaultValue={proximaQuartaDepoisDe(hoje)}
              />
            </FormAcao>
          </details>

          <details>
            <summary>Horário</summary>
            <FormAcao acao={definirHorarioEntrega} rotulo="Salvar horário">
              <input type="hidden" name="entrega_id" value={entregaId} />
              <label htmlFor={`hr-${entregaId}`}>Horário previsto (vazio = sem horário)</label>
              <input id={`hr-${entregaId}`} name="horario" type="time" defaultValue={horario ?? ''} />
            </FormAcao>
          </details>

          <details>
            <summary>Cancelar esta entrega</summary>
            <FormAcao acao={marcarEntrega} rotulo="Cancelar entrega">
              <input type="hidden" name="entrega_id" value={entregaId} />
              <input type="hidden" name="situacao" value="cancelada" />
              <label htmlFor={`obs-c-${entregaId}`}>Motivo (opcional)</label>
              <input id={`obs-c-${entregaId}`} name="observacao" maxLength={500} />
            </FormAcao>
          </details>
        </>
      )}

      {status === 'entregue' && (
        <details>
          <summary>Registrar defeito</summary>
          <FormAcao acao={registrarDefeito} rotulo="Registrar defeito" limpar>
            <input type="hidden" name="entrega_id" value={entregaId} />
            <label htmlFor={`qd-${entregaId}`}>Ovos com defeito</label>
            <input id={`qd-${entregaId}`} name="quantidade" inputMode="numeric" required />
            <label htmlFor={`dd-${entregaId}`}>Descrição</label>
            <input id={`dd-${entregaId}`} name="descricao" required minLength={3} maxLength={500} />
          </FormAcao>
          <p className="suave">A reposição vai sem custo na próxima entrega.</p>
        </details>
      )}

      <details>
        <summary>Observação</summary>
        <FormAcao acao={salvarObservacaoEntrega} rotulo="Salvar observação">
          <input type="hidden" name="entrega_id" value={entregaId} />
          <label htmlFor={`obs-${entregaId}`}>Observação</label>
          <textarea id={`obs-${entregaId}`} name="observacao" maxLength={500} defaultValue={observacao ?? ''} />
        </FormAcao>
      </details>
    </div>
  );
}
