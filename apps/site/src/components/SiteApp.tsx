'use client';

import { Navbar } from './Navbar';
import { Hero } from './Hero';
import { PlansSection } from './PlansSection';
import { ComparisonTable } from './ComparisonTable';
import { NeighborhoodSection } from './NeighborhoodSection';
import { FaqSection } from './FaqSection';
import { Footer } from './Footer';

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
        <PlansSection />
        <ComparisonTable />
        <NeighborhoodSection />
        <FaqSection />
      </main>
      <Footer />
    </>
  );
}
