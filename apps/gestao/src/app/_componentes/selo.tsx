import type { ReactNode } from 'react';

export type TomSelo = 'sucesso' | 'alerta' | 'perigo' | 'oliva' | 'neutro';

/** Situação = ponto colorido + texto. A cor nunca é o único sinal. */
export function Selo({ tom = 'neutro', children }: { tom?: TomSelo; children: ReactNode }) {
  return (
    <span className={`selo selo-${tom}`}>
      <span className="selo-ponto" aria-hidden="true" />
      {children}
    </span>
  );
}
