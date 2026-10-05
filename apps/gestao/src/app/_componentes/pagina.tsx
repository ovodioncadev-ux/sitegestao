import Link from 'next/link';
import type { ReactNode } from 'react';
import { SairBotao } from '../sair-botao';

const LINKS = [
  ['/', 'Painel'],
  ['/clientes', 'Clientes'],
  ['/assinaturas', 'Assinaturas'],
  ['/entregas', 'Entregas'],
  ['/faturas', 'Faturas'],
  ['/historico', 'Histórico'],
  ['/area-de-entrega', 'Área de entrega'],
  ['/configuracoes', 'Configurações'],
] as const;

/** Moldura provisória: só o suficiente para navegar entre as telas. Sem design. */
export function Pagina({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <main className="pagina">
      <nav className="menu">
        {LINKS.map(([href, texto]) => (
          <Link key={href} href={href}>
            {texto}
          </Link>
        ))}
        <span className="menu-sair">
          <SairBotao />
        </span>
      </nav>
      <h1>{titulo}</h1>
      {children}
    </main>
  );
}

export function SemPermissao({ mensagem }: { mensagem: string }) {
  return (
    <main className="pagina">
      <p className="msg-erro" role="alert">
        {mensagem}
      </p>
      <p>
        <Link href="/entrar">Entrar</Link>
      </p>
    </main>
  );
}

export function Aviso({ tipo, children }: { tipo: 'ok' | 'erro' | 'info'; children: ReactNode }) {
  return (
    <p className={tipo === 'ok' ? 'msg-ok' : tipo === 'erro' ? 'msg-erro' : 'msg-info'}>{children}</p>
  );
}
