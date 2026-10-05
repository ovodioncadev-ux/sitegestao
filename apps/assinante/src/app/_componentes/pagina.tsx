import Link from 'next/link';
import type { ReactNode } from 'react';
import { SairBotao } from './sair-botao';

export function Pagina({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <main className="pagina">
      <nav className="menu" aria-label="Principal">
        <Link href="/">Minha assinatura</Link>
        <Link href="/dados">Meus dados</Link>
        <span className="menu-sair">
          <SairBotao />
        </span>
      </nav>
      <h1>{titulo}</h1>
      {children}
    </main>
  );
}
