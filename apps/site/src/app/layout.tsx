import type { Metadata, Viewport } from 'next';
import { Aclonica, Poppins } from 'next/font/google';
import '@ovo/ui/tokens.css';
import './globals.css';

// Fontes da marca servidas pelo próprio site (sem requisição externa), só com
// os pesos usados: Aclonica nos títulos (h1/h2) e Poppins 400/600 no resto.
// globals.css liga estas variáveis a --fonte-titulo e --fonte-corpo.
const aclonica = Aclonica({ subsets: ['latin'], weight: '400', variable: '--fonte-aclonica', display: 'swap' });
const poppins = Poppins({
  subsets: ['latin'],
  weight: ['400', '600'],
  variable: '--fonte-poppins',
  display: 'swap',
});

const TITULO = 'Ovo di Onça — Ovos caipiras por assinatura';
const DESCRICAO = 'Ovos caipiras direto da fazenda, com frete grátis na área atendida. Assine em minutos.';

export const metadata: Metadata = {
  title: TITULO,
  description: DESCRICAO,
  openGraph: {
    type: 'website',
    locale: 'pt_BR',
    siteName: 'Ovo di Onça',
    title: TITULO,
    description: DESCRICAO,
  },
  twitter: { card: 'summary', title: TITULO, description: DESCRICAO },
};

export const viewport: Viewport = {
  themeColor: '#fdfbf7',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={`${aclonica.variable} ${poppins.variable}`}>
      <body>{children}</body>
    </html>
  );
}
