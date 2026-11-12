import type {
  InputHTMLAttributes,
  ReactNode,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from 'react';

/**
 * Rótulo sempre visível acima do controle; ajuda e erro embaixo.
 * O controle (Entrada/Selecao/AreaTexto) recebe o mesmo `id` passado aqui.
 */
export function Campo({
  id,
  rotulo,
  ajuda,
  erro,
  obrigatorio,
  children,
}: {
  id: string;
  rotulo: string;
  ajuda?: ReactNode;
  erro?: ReactNode;
  obrigatorio?: boolean;
  children: ReactNode;
}) {
  return (
    <div className="campo">
      <label htmlFor={id}>
        {rotulo}
        {obrigatorio && <span className="campo-obrigatorio"> (obrigatório)</span>}
      </label>
      {children}
      {ajuda && (
        <p id={`${id}-ajuda`} className="campo-ajuda">
          {ajuda}
        </p>
      )}
      {erro && (
        <p id={`${id}-erro`} className="campo-erro" role="alert">
          {erro}
        </p>
      )}
    </div>
  );
}

export function Entrada({ className, ...resto }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={['controle', className].filter(Boolean).join(' ')} {...resto} />;
}

export function Selecao({ className, ...resto }: SelectHTMLAttributes<HTMLSelectElement>) {
  return <select className={['controle', className].filter(Boolean).join(' ')} {...resto} />;
}

export function AreaTexto({ className, ...resto }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea className={['controle', className].filter(Boolean).join(' ')} {...resto} />;
}
