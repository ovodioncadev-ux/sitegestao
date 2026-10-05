'use client';

import { useState, type FormEvent } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { authClient } from '@ovo/database/auth-cliente';

export function FormEntrar({ proximo }: { proximo: string }) {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function aoEnviar(evento: FormEvent) {
    evento.preventDefault();
    setErro(null);
    setEnviando(true);

    const { error } = await authClient.signIn.email({ email: email.trim(), password: senha });

    setEnviando(false);

    if (error) {
      // Mensagem única, de propósito: nunca dizer se o e-mail existe.
      setErro(
        error.status === 429
          ? 'Muitas tentativas. Espere um minuto e tente de novo.'
          : error.status === 403
            ? 'Confirme seu e-mail para entrar. Enviamos um novo link para a sua caixa de entrada.'
            : 'E-mail ou senha incorretos.',
      );
      return;
    }

    router.push(proximo);
    router.refresh();
  }

  const sufixo = proximo !== '/' ? `?proximo=${encodeURIComponent(proximo)}` : '';

  return (
    <main className="estreito">
      <h1>Entrar</h1>
      <p className="suave">Acesse suas entregas e sua assinatura.</p>

      <form onSubmit={aoEnviar}>
        <label className="campo">
          E-mail
          <input type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        </label>

        <label className="campo">
          Senha
          <input
            type="password"
            required
            autoComplete="current-password"
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
          />
        </label>

        {erro && (
          <p role="alert" className="msg-erro">
            {erro}
          </p>
        )}

        <button type="submit" disabled={enviando} className="botao">
          {enviando ? 'Entrando…' : 'Entrar'}
        </button>
      </form>

      <p className="suave">
        Ainda não tem conta? <Link href={`/cadastro${sufixo}`}>Criar conta</Link>
      </p>
    </main>
  );
}
