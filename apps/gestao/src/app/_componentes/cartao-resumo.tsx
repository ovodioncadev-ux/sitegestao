import Link from 'next/link';
import type { ReactNode } from 'react';
import { Icone } from './icone';

/** Um número do Painel. Com `href`, o cartão inteiro leva para a lista. */
export function CartaoResumo({
  rotulo,
  valor,
  detalhe,
  href,
  tom = 'neutro',
}: {
  rotulo: string;
  valor: ReactNode;
  detalhe?: ReactNode;
  href?: string;
  tom?: 'neutro' | 'alerta';
}) {
  const corpo = (
    <>
      <span className="resumo-rotulo">{rotulo}</span>
      <span className="resumo-valor num">{valor}</span>
      {detalhe && <span className="resumo-detalhe">{detalhe}</span>}
      {href && <Icone nome="direita" tamanho={16} className="resumo-seta" />}
    </>
  );
  const classe = `resumo resumo-${tom}`;
  return href ? (
    <Link href={href} className={classe}>
      {corpo}
    </Link>
  ) : (
    <div className={classe}>{corpo}</div>
  );
}
