import Link from 'next/link';

export const metadata = { title: 'Página não encontrada', robots: { index: false } };

export default function NaoEncontrada() {
  return (
    <main className="mx-auto max-w-conteudo px-6 py-24 text-center">
      <h1>Página não encontrada</h1>
      <p className="mt-4 text-suave">O endereço não existe ou mudou de lugar.</p>
      <p className="mt-6">
        <Link href="/" className="underline">Voltar ao início</Link>
      </p>
    </main>
  );
}
