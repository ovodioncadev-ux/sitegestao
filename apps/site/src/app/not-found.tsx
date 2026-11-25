import Link from 'next/link';

export default function NaoEncontrada() {
  return (
    <main style={{ maxWidth: 'var(--largura-conteudo)', margin: '0 auto', padding: 'var(--esp-24) var(--esp-6)' }}>
      <h1 style={{ fontSize: 'var(--texto-titulo)' }}>Página não encontrada</h1>
      <p style={{ color: 'var(--cor-texto-suave)', marginTop: 'var(--esp-4)' }}>
        O endereço que você abriu não existe ou mudou de lugar.
      </p>
      <Link href="/" className="botao-ouro" style={{ marginTop: 'var(--esp-8)' }}>
        Voltar ao início
      </Link>
    </main>
  );
}
