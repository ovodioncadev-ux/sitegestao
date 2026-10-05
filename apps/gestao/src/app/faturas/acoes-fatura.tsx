import { FormAcao } from '../_componentes/form-acao';
import { CHAVES_METODO, METODO_PAGAMENTO } from '@/lib/rotulos';
import { cancelarFatura, registrarPagamento } from './acoes';

/** Ações de uma fatura em aberto (pendente ou atrasada): pagar ou cancelar. */
export function AcoesDaFatura({
  faturaId,
  status,
  hoje,
}: {
  faturaId: string;
  status: string;
  hoje: string;
}) {
  if (status !== 'pendente' && status !== 'atrasada') return <span className="suave">—</span>;

  return (
    <div>
      <details>
        <summary>Registrar pagamento</summary>
        <FormAcao acao={registrarPagamento} rotulo="Confirmar pagamento">
          <input type="hidden" name="fatura_id" value={faturaId} />
          <label htmlFor={`dp-${faturaId}`}>Data do pagamento</label>
          <input id={`dp-${faturaId}`} name="data_pagamento" type="date" defaultValue={hoje} max={hoje} required />
          <label htmlFor={`mp-${faturaId}`}>Método</label>
          <select id={`mp-${faturaId}`} name="metodo" defaultValue="pix" required>
            {CHAVES_METODO.map((m) => (
              <option key={m} value={m}>
                {METODO_PAGAMENTO[m]}
              </option>
            ))}
          </select>
          <label htmlFor={`op-${faturaId}`}>Observação (opcional)</label>
          <input id={`op-${faturaId}`} name="observacao" maxLength={500} />
        </FormAcao>
      </details>

      <details>
        <summary>Cancelar fatura</summary>
        <FormAcao acao={cancelarFatura} rotulo="Cancelar fatura">
          <input type="hidden" name="fatura_id" value={faturaId} />
          <label htmlFor={`mc-${faturaId}`}>Motivo (opcional)</label>
          <input id={`mc-${faturaId}`} name="motivo" maxLength={300} />
        </FormAcao>
      </details>
    </div>
  );
}
