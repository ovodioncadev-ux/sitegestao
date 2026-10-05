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

/**
 * A vitrine não coleta dado de ninguém: "Assinar" leva ao app do assinante
 * (/assinar), onde ficam conta, endereço, confirmação e a criação da
 * assinatura. Assim nenhum dado pessoal trafega por URL nem por formulário
 * do site.
 */
export function SiteApp() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <FaixaConfianca />
        <Pilares />
        <PlansSection />
        <ComoFunciona />
        <ComparisonTable />
        <NeighborhoodSection />
        <FaqSection />
        <CtaFinal />
      </main>
      <Footer />
    </>
  );
}
