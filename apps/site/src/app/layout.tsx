import type { Metadata } from 'next';
import '@ovo/ui/tokens.css';
import './globals.css';

export const metadata: Metadata = {
  title: 'Ovo di Onça — Ovos caipiras por assinatura',
  description: 'Ovos caipiras direto da fazenda, com frete grátis na área atendida. Assine em minutos.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
