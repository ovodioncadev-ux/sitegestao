'use client';

import { Navbar } from './Navbar';
import { Hero } from './Hero';
import { PlansSection } from './PlansSection';
import { ComparisonTable } from './ComparisonTable';
import { NeighborhoodSection } from './NeighborhoodSection';
import { FaqSection } from './FaqSection';
import { Footer } from './Footer';
import { FaixaConfianca } from './FaixaConfianca';
import { Pilares } from './Pilares';
import { ComoFunciona } from './ComoFunciona';
import { CtaFinal } from './CtaFinal';
import type { DadosDoSite } from '@/lib/dados';

/**
 * A vitrine não coleta dado de ninguém: "Assinar" leva ao app do assinante
 * (/assinar), onde ficam conta, endereço, confirmação e a criação da
 * assinatura. Assim nenhum dado pessoal trafega por URL nem por formulário
 * do site.
 */
export function SiteApp({ dados }: { dados?: DadosDoSite }) {
  return (
    <>
      <a href="#conteudo" className="sr-only focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:z-50 focus:rounded-controle focus:bg-superficie focus:px-3 focus:py-2">Ir para o conteúdo</a>
      <Navbar />
      <main id="conteudo">
        <Hero />
        <FaixaConfianca inicial={dados?.conteudo} />
        <Pilares />
        <PlansSection inicial={dados?.planos} />
        <ComoFunciona />
        <ComparisonTable />
        <NeighborhoodSection inicial={dados?.bairros} />
        <FaqSection inicial={dados?.conteudo} />
        <CtaFinal />
      </main>
      <Footer />
    </>
  );
}
