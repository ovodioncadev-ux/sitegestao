import type { ReactNode } from 'react';
import { Icone, type NomeIcone } from './icone';

const ICONE: Record<'ok' | 'erro' | 'info', NomeIcone> = { ok: 'ok', erro: 'alerta', info: 'info' };

/** Faixa de aviso do DS. `ok` anuncia como status, `erro` como alerta. */
export function Aviso({ tipo, children }: { tipo: 'ok' | 'erro' | 'info'; children: ReactNode }) {
  return (
    <div className={`aviso aviso-${tipo}`} role={tipo === 'erro' ? 'alert' : 'status'}>
      <Icone nome={ICONE[tipo]} />
      <div>{children}</div>
    </div>
  );
}
