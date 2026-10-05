import { caminhoInterno } from '@/lib/seguranca';
import { FormEntrar } from './form-entrar';

type Busca = { proximo?: string; voltar?: string };

export default async function Entrar({ searchParams }: { searchParams: Promise<Busca> }) {
  const busca = await searchParams;
  // `proximo` vem da vitrine/cadastro; `voltar` vem do middleware. Os dois são dado de fora: validados aqui.
  const proximo = caminhoInterno(busca.proximo ?? busca.voltar);
  return <FormEntrar proximo={proximo} />;
}
