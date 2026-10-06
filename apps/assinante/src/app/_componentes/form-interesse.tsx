'use client';

import { useState, type FormEvent } from 'react';
import { CONSENTIMENTO_TEXTO } from '@ovo/config/privacidade';

/**
 * Pedido de aviso para quem já criou cadastro e caiu fora da área. Usa a mesma
 * rota pública do site (/api/interesse), com origem "assinar". Telefone e nome
 * já vêm do cadastro da própria pessoa; o consentimento é uma caixa que ela marca.
 */
export function FormInteresse({ cep, nome, telefone }: { cep: string; nome: string; telefone: string }) {
  const [tel, setTel] = useState(telefone);
  const [email, setEmail] = useState('');
  const [aceito, setAceito] = useState(false);
  const [isca, setIsca] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [enviado, setEnviado] = useState(false);

  async function aoEnviar(evento: FormEvent) {
    evento.preventDefault();
    setErro(null);
    if (!aceito) {
      setErro('Marque a autorização para podermos avisar você.');
      return;
    }
    setEnviando(true);
    try {
      const res = await fetch('/api/interesse', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nome, telefone: tel, email, cep, referencia_interna: isca, origem: 'assinar', consentimento: true }),
      });
      if (!res.ok) {
        const corpo = (await res.json().catch(() => ({}))) as { erro?: string };
        setErro(corpo.erro ?? 'Não foi possível registrar agora. Tente de novo em instantes.');
        return;
      }
      setEnviado(true);
    } finally {
      setEnviando(false);
    }
  }

  if (enviado) {
    return (
      <p role="status" className="msg-ok">
        Anotado! Se um dia a entrega chegar ao seu CEP, a gente avisa.
      </p>
    );
  }

  return (
    <form onSubmit={aoEnviar} noValidate>
      <h2>Quer ser avisado quando chegarmos aí?</h2>
      <label className="campo">
        Telefone com DDD
        <input type="tel" autoComplete="tel" value={tel} onChange={(e) => setTel(e.target.value)} />
      </label>
      <label className="campo">
        E-mail (opcional)
        <input type="email" autoComplete="email" maxLength={254} value={email} onChange={(e) => setEmail(e.target.value)} />
      </label>

      <div aria-hidden="true" style={{ position: 'absolute', left: '-9999px', width: 0, height: 0, overflow: 'hidden' }}>
        <label>
          Não preencha este campo
          <input type="text" tabIndex={-1} autoComplete="off" value={isca} onChange={(e) => setIsca(e.target.value)} />
        </label>
      </div>

      <label className="campo" style={{ display: 'flex', gap: 'var(--esp-3)', alignItems: 'flex-start' }}>
        <input
          type="checkbox"
          checked={aceito}
          onChange={(e) => setAceito(e.target.checked)}
          style={{ width: 20, height: 20, marginTop: 4, flexShrink: 0 }}
        />
        <span>{CONSENTIMENTO_TEXTO}</span>
      </label>

      {erro && (
        <p role="alert" className="msg-erro">
          {erro}
        </p>
      )}
      <button type="submit" disabled={enviando} className="botao">
        {enviando ? 'Enviando…' : 'Avise-me'}
      </button>
    </form>
  );
}
