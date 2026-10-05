'use client';

import { urlAssinar } from '@/lib/api';
import { Botao, Container } from './ui';

export function Hero() {
  return (
    <section id="inicio" className="bg-superficie">
      <Container className="py-24 text-center">
        <p className="mb-4 text-[length:var(--texto-pequeno)] font-semibold uppercase tracking-widest text-secundaria">
          Ovos caipiras por assinatura
        </p>
        <h1>Ovos caipiras, da fazenda direto pra sua casa</h1>
        <p className="mx-auto mt-4 max-w-2xl text-[length:var(--texto-medio)] text-suave">
          Máx. 7 dias entre a colheita e a entrega. Frete grátis na área atendida.
        </p>
        <div className="mt-8 flex flex-wrap justify-center gap-3">
          <Botao href={urlAssinar('semanal')} className="text-[length:var(--texto-medio)]">
            Assinar agora
          </Botao>
          <Botao href="#planos" variante="contorno" className="text-[length:var(--texto-medio)]">
            Ver planos
          </Botao>
        </div>
      </Container>
    </section>
  );
}
