'use client';

import { useRouter } from 'next/navigation';
import { authClient } from '@ovo/database/auth-cliente';

export function SairBotao() {
  const router = useRouter();

  async function sair() {
    await authClient.signOut();
    router.push('/entrar');
    router.refresh();
  }

  return (
    <button type="button" onClick={sair} className="botao botao-secundario">
      Sair
    </button>
  );
}
