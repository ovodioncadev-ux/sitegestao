'use client';

import { useActionState, useEffect, useRef, startTransition, type FormEvent, type ReactNode } from 'react';
import type { AcaoDeFormulario } from '@/lib/tipos';

/**
 * Formulário que chama uma Server Action e MOSTRA o resultado: mensagem de
 * sucesso ou de erro, no próprio lugar, sem tela de erro do Next.
 *
 * O envio é feito à mão (onSubmit) e não pelo `action=` do <form>: o `action=`
 * do React 19 zera todos os campos depois de enviar, mesmo quando deu erro —
 * e a pessoa perderia tudo o que digitou.
 */
export function FormAcao({
  acao,
  rotulo,
  children,
  limpar = false,
  secundario = false,
}: {
  acao: AcaoDeFormulario;
  rotulo: string;
  children?: ReactNode;
  /** Zera os campos quando a ação der certo. */
  limpar?: boolean;
  /** Botão de contorno, para ações que não são a principal da tela. */
  secundario?: boolean;
}) {
  const [estado, despachar, pendente] = useActionState(acao, null);
  const formulario = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (estado?.ok && limpar) formulario.current?.reset();
  }, [estado, limpar]);

  function aoEnviar(evento: FormEvent<HTMLFormElement>) {
    evento.preventDefault();
    const dados = new FormData(evento.currentTarget);
    startTransition(() => despachar(dados));
  }

  return (
    <form ref={formulario} onSubmit={aoEnviar}>
      {children}
      <button type="submit" disabled={pendente} className={secundario ? 'botao botao-secundario' : 'botao'}>
        {pendente ? 'Enviando…' : rotulo}
      </button>
      {estado && (
        <p role={estado.ok ? 'status' : 'alert'} className={estado.ok ? 'msg-ok' : 'msg-erro'}>
          {estado.mensagem}
        </p>
      )}
    </form>
  );
}
