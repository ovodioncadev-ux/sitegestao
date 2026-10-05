import type { Metadata } from 'next';
import '@ovo/ui/tokens.css';
import './globals.css';

export const metadata: Metadata = {
  title: 'Área do assinante · Ovo di Onça',
  description: 'Suas entregas, faturas e assinatura da Ovo di Onça.',
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
