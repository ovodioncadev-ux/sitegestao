import type { ReactNode, TdHTMLAttributes, ThHTMLAttributes } from 'react';

/**
 * Tabela do DS: cabeçalho em 14px, célula com 12px, sem listras, sem hover.
 * Valores em R$ e contagens: `numerico` (alinha à direita, IBM Plex Mono).
 * No celular, a mesma informação vai em <ListaCartoes> (veja abaixo).
 */
export function Tabela({ legenda, children }: { legenda: string; children: ReactNode }) {
  return (
    <div className="tabela">
      <table>
        <caption className="so-leitor">{legenda}</caption>
        {children}
      </table>
    </div>
  );
}

export function Th({
  numerico,
  className,
  ...resto
}: { numerico?: boolean } & ThHTMLAttributes<HTMLTableCellElement>) {
  return (
    <th
      scope="col"
      className={[numerico ? 'celula-num' : '', className].filter(Boolean).join(' ') || undefined}
      {...resto}
    />
  );
}

export function Td({
  numerico,
  className,
  ...resto
}: { numerico?: boolean } & TdHTMLAttributes<HTMLTableCellElement>) {
  return (
    <td
      className={[numerico ? 'celula-num num' : '', className].filter(Boolean).join(' ') || undefined}
      {...resto}
    />
  );
}

export type DadoCartao = { rotulo: string; valor: ReactNode; numerico?: boolean };

export function ListaCartoes({ children }: { children: ReactNode }) {
  return <ul className="lista-cartoes">{children}</ul>;
}

/** Uma linha da tabela no celular: título, situação, pares rótulo/valor e ações. */
export function ItemCartao({
  titulo,
  selo,
  dados,
  acoes,
}: {
  titulo: ReactNode;
  selo?: ReactNode;
  dados: DadoCartao[];
  acoes?: ReactNode;
}) {
  return (
    <li className="item-cartao">
      <div className="item-cartao-topo">
        <strong>{titulo}</strong>
        {selo}
      </div>
      <dl className="item-cartao-dados">
        {dados.map((d) => (
          <div key={d.rotulo}>
            <dt>{d.rotulo}</dt>
            <dd className={d.numerico ? 'num' : undefined}>{d.valor}</dd>
          </div>
        ))}
      </dl>
      {acoes && <div className="item-cartao-acoes">{acoes}</div>}
    </li>
  );
}
