import { confirmacaoDeEmailAtiva } from '@ovo/database/auth';
import { caminhoInterno } from '@/lib/seguranca';
import { FormCadastro } from './form-cadastro';

type Busca = { proximo?: string };

export default async function Cadastro({ searchParams }: { searchParams: Promise<Busca> }) {
  const busca = await searchParams;
  return (
    <FormCadastro
      proximo={caminhoInterno(busca.proximo)}
      exigeConfirmacaoDeEmail={confirmacaoDeEmailAtiva}
    />
  );
}
