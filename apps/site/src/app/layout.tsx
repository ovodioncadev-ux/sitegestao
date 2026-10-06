import type { Metadata } from 'next';
import { Aclonica, Poppins } from 'next/font/google';
import '@ovo/ui/tokens.css';
import './globals.css';
import { NOME_DO_SITE, descricaoDaHome, urlDoSite } from '@/lib/seo';

const aclonica = Aclonica({ weight: '400', subsets: ['latin'], display: 'swap', variable: '--font-aclonica' });
const poppins = Poppins({
  weight: ['400', '500', '600'],
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-poppins',
});

export const metadata: Metadata = {
  metadataBase: new URL(urlDoSite()),
  title: { default: 'Ovo di Onça — Ovos caipiras por assinatura', template: '%s | Ovo di Onça' },
  description: descricaoDaHome(null),
  alternates: { canonical: '/' },
  openGraph: {
    type: 'website',
    locale: 'pt_BR',
    siteName: NOME_DO_SITE,
    title: 'Ovo di Onça — Ovos caipiras por assinatura',
    description: descricaoDaHome(null),
    url: '/',
  },
  twitter: { card: 'summary_large_image' },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={`${aclonica.variable} ${poppins.variable}`}>
      <body>{children}</body>
    </html>
  );
}
