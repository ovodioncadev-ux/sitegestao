const CAMINHOS = {
  folha: 'M5 19c0-8 5-13 14-14 0 9-5 14-13 14M5 19l7-7',
  caminhao: 'M3 7h11v9H3zM14 10h4l3 3v3h-7zM7 19a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM17 19a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z',
  calendario: 'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4',
  relogio: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3 2',
  selo: 'M12 3l2.5 2 3.2-.3.8 3.1 2.5 2-1.2 3 .3 3.2-3.1.8-2 2.5-3-1.2-3.2.3-.8-3.1-2.5-2 1.2-3-.3-3.2 3.1-.8z',
  check: 'M5 12.5l4.5 4.5L19 7.5',
} as const;

export type NomeIcone = keyof typeof CAMINHOS;

/** Ícone decorativo (aria-hidden): o texto ao lado já diz tudo. */
export function Icone({ nome, className = 'h-6 w-6' }: { nome: NomeIcone; className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={className}
    >
      <path d={CAMINHOS[nome]} />
    </svg>
  );
}
