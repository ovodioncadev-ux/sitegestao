'use client';

import { useActionState, useEffect, useRef, startTransition, type FormEvent, type ReactNode } from 'react';
import type { AcaoDeFormulario } from '@/lib/tipos';

/**
 * Formulário que chama uma Server Action e MOSTRA o resultado: mensagem de
 * sucesso ou de erro, no próprio lugar, sem tela de erro do Next.
 *
 * O envio é feito à mão (onSubmit) e não pelo `action=` do <form> de propósito:
 * o `action=` do React 19 zera todos os campos depois de enviar, mesmo quando
 * deu erro — e a pessoa perderia tudo o que digitou. Assim, o formulário só é
 * limpo (limpar) quando a ação deu certo.
 *
 * Os campos entram como `children`, montados no servidor.
 */
export function FormAcao({
  acao,
  rotulo,
  children,
  limpar = false,
  linha = false,
  perigo = false,
  confirmar,
}: {
  acao: AcaoDeFormulario;
  rotulo: string;
  children?: ReactNode;
  /** Zera os campos quando a ação der certo (formulários de "novo"). */
  limpar?: boolean;
  /** Campos e botão lado a lado (botões de ação dentro de tabela). */
  linha?: boolean;
  /** Ação destrutiva: botão em vermelho. */
  perigo?: boolean;
  /** Pergunta de confirmação antes de enviar (use em ações que não têm volta). */
  confirmar?: string;
}) {
  const [estado, despachar, pendente] = useActionState(acao, null);
  const formulario = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (estado?.ok && limpar) formulario.current?.reset();
  }, [estado, limpar]);

  function aoEnviar(evento: FormEvent<HTMLFormElement>) {
    evento.preventDefault();
    if (confirmar && !window.confirm(confirmar)) return;
    const dados = new FormData(evento.currentTarget);
    startTransition(() => despachar(dados));
  }

  return (
    <form ref={formulario} onSubmit={aoEnviar} className={linha ? 'form-linha' : undefined}>
      {children}
      <button type="submit" disabled={pendente} className={perigo ? 'perigo' : undefined}>
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
