import type { AnchorHTMLAttributes, ButtonHTMLAttributes, ReactNode } from 'react';

type Variante = 'primario' | 'contorno' | 'whatsapp' | 'claro';

const BASE =
  'inline-flex min-h-controle items-center justify-center rounded-controle px-6 py-2 font-medium transition-colors';

const VARIANTES: Record<Variante, string> = {
  primario: 'bg-ouro text-sobre-ouro hover:brightness-95',
  contorno: 'border border-ouro bg-transparent text-ouro-escuro hover:bg-fundo-alt',
  whatsapp: 'bg-whatsapp text-sobre-escuro hover:opacity-90',
  /** Sobre fundo escuro (faixa verde). */
  claro: 'bg-sobre-escuro text-ouro-escuro hover:bg-fundo-alt',
};

type Comum = { variante?: Variante; children: ReactNode; className?: string };
type ComoLink = Comum & { href: string } & Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'className' | 'children'>;
type ComoBotao = Comum & { href?: undefined } & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'className' | 'children'>;

/** Renderiza <a> quando recebe href; senão, <button>. */
export function Botao(props: ComoLink | ComoBotao) {
  const { variante = 'primario', className = '', children, ...resto } = props;
  const classes = `${BASE} ${VARIANTES[variante]} ${className}`;
  if (props.href !== undefined) {
    const { href, ...link } = resto as Omit<ComoLink, 'variante' | 'className' | 'children'>;
    return (
      <a href={href} className={classes} {...link}>
        {children}
      </a>
    );
  }
  const botao = resto as Omit<ComoBotao, 'variante' | 'className' | 'children'>;
  return (
    <button type="button" className={classes} {...botao}>
      {children}
    </button>
  );
}
