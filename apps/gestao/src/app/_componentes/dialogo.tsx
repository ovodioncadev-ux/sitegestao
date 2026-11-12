'use client';

import { useEffect, useId, useRef, type ReactNode } from 'react';

/**
 * Diálogo modal em cima do <dialog> nativo: o navegador prende o foco dentro,
 * fecha com Esc e devolve o foco ao botão de origem. Aqui entram só o clique
 * fora e o foco inicial (no elemento com data-foco-inicial, o "Cancelar").
 * Desktop: caixa no centro. Celular: painel que sobe do rodapé.
 */
export function Dialogo({
  aberto,
  aoFechar,
  titulo,
  children,
}: {
  aberto: boolean;
  aoFechar: () => void;
  titulo: string;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const tituloId = useId();

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (aberto && !d.open) {
      d.showModal();
      d.querySelector<HTMLElement>('[data-foco-inicial]')?.focus();
    }
    if (!aberto && d.open) d.close();
  }, [aberto]);

  return (
    <dialog
      ref={ref}
      className="dialogo"
      role="dialog"
      aria-modal="true"
      aria-labelledby={tituloId}
      onCancel={(e) => {
        e.preventDefault();
        aoFechar();
      }}
      onClose={aoFechar}
      onClick={(e) => {
        if (e.target === e.currentTarget) aoFechar();
      }}
    >
      <div className="dialogo-corpo">
        <h2 id={tituloId}>{titulo}</h2>
        {children}
      </div>
    </dialog>
  );
}
