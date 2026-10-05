'use client';

import { useState, type FormEvent } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { authClient } from '@ovo/database/auth-cliente';

const SENHA_MINIMA = 12; // o mesmo valor que o servidor exige (better-auth.ts)

export function FormCadastro({
  proximo,
  exigeConfirmacaoDeEmail,
}: {
  proximo: string;
  /** Há serviço de e-mail: a conta só entra depois de clicar no link enviado. */
  exigeConfirmacaoDeEmail: boolean;
}) {
  const router = useRouter();
  const [nome, setNome] = useState('');
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroGeral, setErroGeral] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const [aguardandoConfirmacao, setAguardandoConfirmacao] = useState(false);

  async function aoEnviar(evento: FormEvent) {
    evento.preventDefault();
    setErroGeral(null);

    const novos: Record<string, string> = {};
    if (nome.trim().length < 3) novos.nome = 'Informe seu nome (pelo menos 3 letras).';
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) novos.email = 'Informe um e-mail válido.';
    if (senha.length < SENHA_MINIMA) novos.senha = `A senha precisa ter pelo menos ${SENHA_MINIMA} caracteres.`;
    setErros(novos);
    if (Object.keys(novos).length > 0) return;

    setEnviando(true);
    const { error } = await authClient.signUp.email({
      name: nome.trim(),
      email: email.trim(),
      password: senha,
      // Onde a pessoa cai depois de clicar no link do e-mail (só usado com confirmação).
      callbackURL: proximo,
    });
    setEnviando(false);

    if (error) {
      // Não confirmamos se o e-mail já tem conta: mensagem única.
      setErroGeral(
        error.status === 429
          ? 'Muitas tentativas. Espere um minuto e tente de novo.'
          : 'Não foi possível criar a conta. Confira os dados ou tente entrar.',
      );
      return;
    }

    if (exigeConfirmacaoDeEmail) {
      setAguardandoConfirmacao(true);
      return;
    }

    router.push(proximo);
    router.refresh();
  }

  const sufixo = proximo !== '/' ? `?proximo=${encodeURIComponent(proximo)}` : '';

  if (aguardandoConfirmacao) {
    return (
      <main className="estreito">
        <h1>Confirme seu e-mail</h1>
        <p role="status" className="suave">
          Enviamos um link para {email.trim()}. Clique nele para ativar a conta e depois{' '}
          <Link href={`/entrar${sufixo}`}>entre</Link> para continuar.
        </p>
      </main>
    );
  }

  return (
    <main className="estreito">
      <h1>Criar conta</h1>
      <p className="suave">Primeiro a conta; o endereço e o plano vêm no passo seguinte.</p>

      <form onSubmit={aoEnviar} noValidate>
        <label className="campo">
          Nome
          <input
            type="text"
            autoComplete="name"
            value={nome}
            onChange={(e) => setNome(e.target.value)}
            aria-invalid={Boolean(erros.nome)}
          />
          {erros.nome && <span role="alert" className="msg-erro">{erros.nome}</span>}
        </label>

        <label className="campo">
          E-mail
          <input
            type="email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            aria-invalid={Boolean(erros.email)}
          />
          {erros.email && <span role="alert" className="msg-erro">{erros.email}</span>}
        </label>

        <label className="campo">
          Senha (mínimo {SENHA_MINIMA} caracteres)
          <input
            type="password"
            autoComplete="new-password"
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
            aria-invalid={Boolean(erros.senha)}
          />
          {erros.senha && <span role="alert" className="msg-erro">{erros.senha}</span>}
        </label>

        {erroGeral && (
          <p role="alert" className="msg-erro">
            {erroGeral}
          </p>
        )}

        <button type="submit" disabled={enviando} className="botao">
          {enviando ? 'Criando…' : 'Criar conta'}
        </button>
      </form>

      <p className="suave">
        Já tem conta? <Link href={`/entrar${sufixo}`}>Entrar</Link>
      </p>
    </main>
  );
}
