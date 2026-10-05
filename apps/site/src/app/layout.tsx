import type { Metadata } from 'next';
import { Aclonica, Poppins } from 'next/font/google';
import '@ovo/ui/tokens.css';
import './globals.css';

const aclonica = Aclonica({ weight: '400', subsets: ['latin'], display: 'swap', variable: '--font-aclonica' });
const poppins = Poppins({
  weight: ['400', '500', '600', '700'],
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-poppins',
});

export const metadata: Metadata = {
  title: 'Ovo di Onça — Ovos caipiras por assinatura',
  description: 'Ovos caipiras direto da fazenda, com frete grátis na área atendida. Assine em minutos.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={`${aclonica.variable} ${poppins.variable}`}>
      <body>{children}</body>
    </html>
  );
}
