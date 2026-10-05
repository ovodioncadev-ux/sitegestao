'use client';

import { urlAssinar } from '@/lib/api';
import { Botao, Container } from './ui';

export function CtaFinal() {
  return (
    <section className="bg-secundaria text-sobre-ouro">
      <Container className="py-16 text-center">
        <h2 className="text-[length:var(--texto-titulo)]">Comece a receber ovos de verdade</h2>
        <p className="mx-auto mt-3 max-w-xl">Escolha o plano, confira seu CEP e assine em poucos minutos.</p>
        <Botao href={urlAssinar('semanal')} variante="claro" className="mt-6">
          Assinar agora
        </Botao>
      </Container>
    </section>
  );
}
