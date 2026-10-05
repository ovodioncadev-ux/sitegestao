'use client';

import { urlAssinar } from '@/lib/api';
import { Botao, Container } from './ui';

export function Hero() {
  return (
    <section id="inicio">
      <Container className="py-24 text-center">
        <h1>Ovos caipiras, da fazenda direto pra sua casa</h1>
        <p className="mt-4 text-[length:var(--texto-medio)] text-suave">
          Máx. 7 dias entre a colheita e a entrega. Frete grátis na área atendida.
        </p>
        <Botao href={urlAssinar('semanal')} className="mt-8 text-[length:var(--texto-medio)]">
          Assinar agora
        </Botao>
      </Container>
    </section>
  );
}
