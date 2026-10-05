import type { ReactNode } from 'react';

export function Selo({ children }: { children: ReactNode }) {
  return (
    <span className="absolute right-3 top-3 rounded-pilula bg-ouro-app px-3 py-1 text-[length:var(--texto-rotulo)] text-texto">
      {children}
    </span>
  );
}
