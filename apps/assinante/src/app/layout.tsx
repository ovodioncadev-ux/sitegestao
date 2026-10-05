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
  title: 'Área do assinante · Ovo di Onça',
  description: 'Suas entregas, faturas e assinatura da Ovo di Onça.',
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={`${aclonica.variable} ${poppins.variable}`}>
      <body>{children}</body>
    </html>
  );
}
