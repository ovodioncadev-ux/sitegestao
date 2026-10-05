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
    <button
      onClick={sair}
      style={{
        border: '1px solid var(--cor-texto)',
        background: 'transparent',
        color: 'var(--cor-texto)',
        height: 'var(--altura-controle)',
        padding: '0 var(--esp-4)',
        borderRadius: 'var(--raio-controle)',
        fontFamily: 'var(--fonte-corpo)',
        fontSize: 'var(--texto-pequeno)',
        cursor: 'pointer',
      }}
    >
      Sair
    </button>
  );
}
