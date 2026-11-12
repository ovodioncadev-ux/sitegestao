import type { ReactNode } from 'react';

/** Lista sem resultado: diz o que aconteceu e oferece a saída. */
export function Vazio({
  titulo,
  children,
  acao,
}: {
  titulo: string;
  children?: ReactNode;
  acao?: ReactNode;
}) {
  return (
    <div className="vazio">
      <h3>{titulo}</h3>
      {children && <p>{children}</p>}
      {acao && <div className="vazio-acao">{acao}</div>}
    </div>
  );
}
