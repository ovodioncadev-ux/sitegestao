'use client';

import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { authClient } from '@ovo/database/auth-cliente';

export default function Entrar() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function aoEnviar(evento: FormEvent) {
    evento.preventDefault();
    setErro(null);
    setEnviando(true);

    try {
      const { error } = await authClient.signIn.email({ email, password: senha });

      if (error) {
        // Só diz "senha incorreta" quando o servidor realmente recusou as
        // credenciais; qualquer outra falha é do sistema, não da pessoa.
        if (error.status === 401 || error.status === 400) {
          setErro('E-mail ou senha incorretos.');
        } else if (error.status === 429) {
          setErro('Muitas tentativas. Aguarde um minuto e tente de novo.');
        } else {
          setErro('Não foi possível entrar agora. Tente de novo em instantes.');
        }
        return;
      }

      router.push('/');
      router.refresh();
    } catch {
      setErro('Não foi possível entrar agora. Confira a conexão e tente de novo.');
    } finally {
      setEnviando(false);
    }
  }

  return (
    <main
      style={{
        maxWidth: '400px',
        margin: '0 auto',
        padding: 'var(--esp-24) var(--esp-6)',
      }}
    >
      <h1 style={{ fontSize: 'var(--texto-titulo)' }}>Painel do dono</h1>
      <p style={{ color: 'var(--cor-texto-suave)', marginTop: 'var(--esp-2)', marginBottom: 'var(--esp-8)' }}>
        Entre com seu e-mail e senha.
      </p>

      <form onSubmit={aoEnviar}>
        <label htmlFor="email" style={{ display: 'block', marginBottom: 'var(--esp-1)' }}>
          E-mail
        </label>
        <input
          id="email"
          type="email"
          required
          autoComplete="email"
          value={email}
          onChange={(evento) => setEmail(evento.target.value)}
          style={{
            width: '100%',
            height: 'var(--altura-controle)',
            border: '1px solid var(--cor-borda)',
            borderRadius: 'var(--raio-controle)',
            padding: '0 var(--esp-3)',
            fontSize: 'var(--texto-corpo)',
            marginBottom: 'var(--esp-4)',
          }}
        />

        <label htmlFor="senha" style={{ display: 'block', marginBottom: 'var(--esp-1)' }}>
          Senha
        </label>
        <input
          id="senha"
          type="password"
          required
          autoComplete="current-password"
          value={senha}
          onChange={(evento) => setSenha(evento.target.value)}
          style={{
            width: '100%',
            height: 'var(--altura-controle)',
            border: '1px solid var(--cor-borda)',
            borderRadius: 'var(--raio-controle)',
            padding: '0 var(--esp-3)',
            fontSize: 'var(--texto-corpo)',
            marginBottom: 'var(--esp-4)',
          }}
        />

        {erro && (
          <p role="alert" style={{ color: 'var(--cor-erro)', marginBottom: 'var(--esp-4)' }}>
            {erro}
          </p>
        )}

        <button
          type="submit"
          disabled={enviando}
          style={{
            width: '100%',
            height: 'var(--altura-controle)',
            borderRadius: 'var(--raio-controle)',
            border: 'none',
            background: 'var(--cor-ouro)',
            color: 'var(--cor-texto)',
            fontFamily: 'var(--fonte-corpo)',
            fontWeight: 600,
            fontSize: 'var(--texto-corpo)',
            cursor: enviando ? 'default' : 'pointer',
            opacity: enviando ? 0.7 : 1,
          }}
        >
          {enviando ? 'Entrando…' : 'Entrar'}
        </button>
      </form>
    </main>
  );
}
