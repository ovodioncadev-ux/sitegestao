import type { ReactNode } from 'react';

export function Cartao({
  children,
  destaque = false,
  className = '',
}: {
  children: ReactNode;
  destaque?: boolean;
  className?: string;
}) {
  const borda = destaque ? 'border-2 border-ouro' : 'border border-borda';
  return <article className={`relative rounded-card bg-fundo p-6 ${borda} ${className}`}>{children}</article>;
}
