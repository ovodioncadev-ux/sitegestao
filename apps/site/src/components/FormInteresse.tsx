'use client';

import { useState, type FormEvent } from 'react';
import { CONSENTIMENTO_TEXTO } from '@ovo/config/privacidade';
import { registrarInteresse } from '@/lib/api';
import { mascararTelefone } from '@/lib/formatar';
import { Botao } from './ui';

const CAMPO = 'min-h-controle w-full rounded-controle border border-borda px-3';

/**
 * "Avise-me quando chegar ao meu CEP". Pede só o necessário (telefone OU e-mail),
 * o consentimento é uma caixa que a pessoa marca (nunca pré-marcada) e o texto
 * dele vem de @ovo/config. O campo `referencia_interna` é uma isca para robôs: fica fora da
 * tela e do teclado, e quem o preenche é descartado no servidor.
 */
export function FormInteresse({ cep }: { cep: string }) {
  const [nome, setNome] = useState('');
  const [telefone, setTelefone] = useState('');
  const [email, setEmail] = useState('');
  const [aceito, setAceito] = useState(false);
  const [isca, setIsca] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [enviado, setEnviado] = useState(false);

  async function aoEnviar(evento: FormEvent) {
    evento.preventDefault();
    setErro(null);
    if (!telefone.trim() && !email.trim()) {
      setErro('Informe um telefone ou um e-mail para receber o aviso.');
      return;
    }
    if (!aceito) {
      setErro('Marque a autorização para podermos avisar você.');
      return;
    }
    setEnviando(true);
    try {
      await registrarInteresse({ nome, telefone, email, cep, referencia_interna: isca });
      setEnviado(true);
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível registrar agora.');
    } finally {
      setEnviando(false);
    }
  }

  if (enviado) {
    return (
      <p role="status" className="mt-4 rounded-card bg-secundaria-suave p-4 text-texto">
        Anotado! Se um dia a entrega chegar ao seu CEP, a gente avisa.
      </p>
    );
  }

  return (
    <form onSubmit={aoEnviar} noValidate className="mx-auto mt-6 max-w-md rounded-card border border-borda p-6 text-left">
      <h3 className="font-semibold">Quer ser avisado quando chegarmos aí?</h3>
      <p className="mt-1 text-[length:var(--texto-pequeno)] text-suave">
        Deixe um contato. Telefone ou e-mail já bastam.
      </p>

      <label className="mt-4 block">
        Nome (opcional)
        <input className={CAMPO} type="text" autoComplete="name" maxLength={120} value={nome} onChange={(e) => setNome(e.target.value)} />
      </label>
      <label className="mt-3 block">
        Telefone com DDD
        <input
          className={CAMPO}
          type="tel"
          inputMode="tel"
          autoComplete="tel"
          value={telefone}
          onChange={(e) => setTelefone(mascararTelefone(e.target.value))}
        />
      </label>
      <label className="mt-3 block">
        E-mail
        <input className={CAMPO} type="email" autoComplete="email" maxLength={254} value={email} onChange={(e) => setEmail(e.target.value)} />
      </label>

      {/* Isca para robôs: fora da tela, fora do teclado, fora dos leitores de tela. */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-0 w-0 overflow-hidden">
        <label>
          Não preencha este campo
          <input type="text" name="referencia_interna" tabIndex={-1} autoComplete="off" value={isca} onChange={(e) => setIsca(e.target.value)} />
        </label>
      </div>

      <label className="mt-4 flex items-start gap-3 text-[length:var(--texto-pequeno)]">
        <input
          type="checkbox"
          checked={aceito}
          onChange={(e) => setAceito(e.target.checked)}
          className="mt-1 h-5 w-5 shrink-0"
        />
        <span>{CONSENTIMENTO_TEXTO}</span>
      </label>

      {erro && (
        <p role="alert" className="mt-3 text-erro">
          {erro}
        </p>
      )}
      <Botao type="submit" disabled={enviando} className="mt-4 w-full">
        {enviando ? 'Enviando…' : 'Avise-me'}
      </Botao>
    </form>
  );
}
