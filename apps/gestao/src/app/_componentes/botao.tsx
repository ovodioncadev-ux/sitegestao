import Link from 'next/link';
import type { AnchorHTMLAttributes, ButtonHTMLAttributes, ReactNode } from 'react';
import { Icone, type NomeIcone } from './icone';

export type VarianteBotao = 'primario' | 'secundario' | 'perigo' | 'perigoSolido' | 'fantasma';
export type TamanhoBotao = 'm' | 'g';

type Visual = {
  variante?: VarianteBotao;
  tamanho?: TamanhoBotao;
  icone?: NomeIcone;
  iconeDepois?: NomeIcone;
  cheio?: boolean;
};

/** Classes do botão — também serve para estilizar um <a> ou um <summary>. */
export function classeBotao({ variante = 'primario', tamanho = 'm', cheio = false }: Visual = {}) {
  return ['btn', `btn-${variante}`, `btn-${tamanho}`, cheio ? 'btn-cheio' : ''].filter(Boolean).join(' ');
}

function Conteudo({ icone, iconeDepois, children }: Visual & { children: ReactNode }) {
  return (
    <>
      {icone && <Icone nome={icone} tamanho={16} />}
      {children}
      {iconeDepois && <Icone nome={iconeDepois} tamanho={16} />}
    </>
  );
}

export function Botao({
  variante,
  tamanho,
  icone,
  iconeDepois,
  cheio,
  className,
  type = 'button',
  children,
  ...resto
}: Visual & ButtonHTMLAttributes<HTMLButtonElement>) {
  const classes = [classeBotao({ variante, tamanho, cheio }), className].filter(Boolean).join(' ');
  return (
    <button type={type} className={classes} {...resto}>
      <Conteudo icone={icone} iconeDepois={iconeDepois}>
        {children}
      </Conteudo>
    </button>
  );
}

export function LinkBotao({
  href,
  variante,
  tamanho,
  icone,
  iconeDepois,
  cheio,
  className,
  children,
  ...resto
}: Visual & { href: string } & Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'href'>) {
  const classes = [classeBotao({ variante, tamanho, cheio }), className].filter(Boolean).join(' ');
  return (
    <Link href={href} className={classes} {...resto}>
      <Conteudo icone={icone} iconeDepois={iconeDepois}>
        {children}
      </Conteudo>
    </Link>
  );
}
