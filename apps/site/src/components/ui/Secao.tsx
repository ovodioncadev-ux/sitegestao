import type { ReactNode } from 'react';
import { Container } from './Container';

type Props = {
  id?: string;
  titulo?: string;
  subtitulo?: string;
  /** Fundo da faixa: padrão (página) ou alternado. */
  fundo?: 'padrao' | 'baixo';
  children: ReactNode;
};

export function Secao({ id, titulo, subtitulo, fundo = 'padrao', children }: Props) {
  return (
    <section id={id} className={fundo === 'baixo' ? 'bg-superficie-baixa' : undefined}>
      <Container className="py-16">
        {titulo && <h2 className="text-center text-[length:var(--texto-titulo)]">{titulo}</h2>}
        {subtitulo && <p className="mx-auto mt-3 max-w-2xl text-center text-suave">{subtitulo}</p>}
        <div className={titulo ? 'mt-8' : undefined}>{children}</div>
      </Container>
    </section>
  );
}
