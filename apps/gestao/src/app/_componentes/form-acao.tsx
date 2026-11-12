'use client';

import {
  useActionState,
  useEffect,
  useId,
  useRef,
  useState,
  startTransition,
  type FormEvent,
  type ReactNode,
} from 'react';
import type { AcaoDeFormulario } from '@/lib/tipos';
import { Aviso } from './aviso';
import { Botao, type VarianteBotao } from './botao';
import { Dialogo } from './dialogo';

export type Confirmacao = {
  /** Pergunta do diálogo, com o nome do registro: "Cancelar a assinatura de Maria?" */
  titulo: string;
  /** O que acontece ao confirmar. */
  descricao: ReactNode;
  /** Texto do botão que confirma. Padrão: o próprio rótulo da ação. */
  rotuloConfirmar?: string;
  /** Texto do botão que desiste. Padrão: "Voltar". */
  rotuloVoltar?: string;
};

/**
 * Formulário que chama uma Server Action e MOSTRA o resultado: mensagem de
 * sucesso ou de erro, no próprio lugar, sem tela de erro do Next.
 *
 * O envio é feito à mão (onSubmit) e não pelo `action=` do <form> de propósito:
 * o `action=` do React 19 zera todos os campos depois de enviar, mesmo quando
 * deu erro — e a pessoa perderia tudo o que digitou. Assim, o formulário só é
 * limpo (limpar) quando a ação deu certo.
 *
 * Com `confirmar`, o botão abre um diálogo e só envia depois do "sim". A ação
 * de servidor chamada é a mesma; o diálogo é só uma etapa a mais na tela.
 *
 * Os campos entram como `children`, montados no servidor.
 */
export function FormAcao({
  acao,
  rotulo,
  children,
  limpar = false,
  linha = false,
  variante = 'primario',
  confirmar,
}: {
  acao: AcaoDeFormulario;
  rotulo: string;
  children?: ReactNode;
  /** Zera os campos quando a ação der certo (formulários de "novo"). */
  limpar?: boolean;
  /** Campos e botão lado a lado (botões de ação dentro de tabela). */
  linha?: boolean;
  variante?: VarianteBotao;
  /** Pede confirmação antes de enviar (ações que desfazem algo). */
  confirmar?: Confirmacao;
}) {
  const [estado, despachar, pendente] = useActionState(acao, null);
  const formulario = useRef<HTMLFormElement>(null);
  const idFormulario = useId();
  const [aberto, setAberto] = useState(false);

  useEffect(() => {
    if (estado?.ok && limpar) formulario.current?.reset();
  }, [estado, limpar]);

  function aoEnviar(evento: FormEvent<HTMLFormElement>) {
    evento.preventDefault();
    const dados = new FormData(evento.currentTarget);
    setAberto(false);
    startTransition(() => despachar(dados));
  }

  return (
    <form
      id={idFormulario}
      ref={formulario}
      onSubmit={aoEnviar}
      className={linha ? 'form-linha' : undefined}
    >
      {children}
      {confirmar ? (
        <>
          <Botao variante={variante} disabled={pendente} onClick={() => setAberto(true)}>
            {pendente ? 'Enviando…' : rotulo}
          </Botao>
          <Dialogo aberto={aberto} aoFechar={() => setAberto(false)} titulo={confirmar.titulo}>
            <div className="dialogo-texto">{confirmar.descricao}</div>
            <div className="dialogo-acoes">
              <Botao variante="secundario" data-foco-inicial onClick={() => setAberto(false)}>
                {confirmar.rotuloVoltar ?? 'Voltar'}
              </Botao>
              {/* Fora do <form> no DOM, mas ligado a ele pelo atributo form. */}
              <Botao
                type="submit"
                form={idFormulario}
                variante={variante === 'perigo' ? 'perigoSolido' : variante}
              >
                {confirmar.rotuloConfirmar ?? rotulo}
              </Botao>
            </div>
          </Dialogo>
        </>
      ) : (
        <Botao type="submit" variante={variante} disabled={pendente}>
          {pendente ? 'Enviando…' : rotulo}
        </Botao>
      )}
      {estado && <Aviso tipo={estado.ok ? 'ok' : 'erro'}>{estado.mensagem}</Aviso>}
    </form>
  );
}
