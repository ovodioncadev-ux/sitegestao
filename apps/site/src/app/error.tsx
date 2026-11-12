'use client';

import { useEffect } from 'react';

export default function Erro({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    // O detalhe técnico fica só no console; o visitante vê uma mensagem fixa.
    console.error('Erro na vitrine:', error);
  }, [error]);

  return (
    <main
      role="alert"
      style={{ maxWidth: 'var(--largura-conteudo)', margin: '0 auto', padding: 'var(--esp-24) var(--esp-6)' }}
    >
      <h1 style={{ fontSize: 'var(--texto-titulo)' }}>Algo deu errado</h1>
      <p style={{ color: 'var(--cor-texto-suave)', marginTop: 'var(--esp-4)' }}>
        Não conseguimos mostrar esta página agora. Tente de novo em instantes.
      </p>
      <button type="button" className="botao-contorno" onClick={reset} style={{ marginTop: 'var(--esp-8)' }}>
        Tentar de novo
      </button>
    </main>
  );
}
