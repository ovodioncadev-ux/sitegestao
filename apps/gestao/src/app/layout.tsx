import type { Metadata } from 'next';
import { Archivo, IBM_Plex_Mono, Outfit } from 'next/font/google';
import '@ovo/ui/tokens.css';
import '@ovo/ui/ds.css';
import './globals.css';
import './componentes.css';

// Fontes do Design System, servidas pelo próprio app (sem requisição externa).
const outfit = Outfit({ subsets: ['latin'], variable: '--fonte-outfit', display: 'swap' });
const archivo = Archivo({ subsets: ['latin'], variable: '--fonte-archivo', display: 'swap' });
const plex = IBM_Plex_Mono({
  subsets: ['latin'],
  weight: ['400', '500', '600'],
  variable: '--fonte-plex',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Painel do dono · Ovo di Onça',
  description: 'Controle interno das assinaturas da Ovo di Onça.',
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={`${outfit.variable} ${archivo.variable} ${plex.variable}`}>
      <body>{children}</body>
    </html>
  );
}
