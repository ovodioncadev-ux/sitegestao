import { confirmacaoDeEmailAtiva } from '@ovo/database/auth';
import { caminhoInterno } from '@/lib/seguranca';
import { CabecalhoFunil, passoPeloDestino } from '../_componentes/funil';
import { FormCadastro } from './form-cadastro';

type Busca = { proximo?: string };

export default async function Cadastro({ searchParams }: { searchParams: Promise<Busca> }) {
  const busca = await searchParams;
  const proximo = caminhoInterno(busca.proximo);
  return (
    <>
      <CabecalhoFunil passo={passoPeloDestino(proximo)} />
      <FormCadastro proximo={proximo} exigeConfirmacaoDeEmail={confirmacaoDeEmailAtiva} />
    </>
  );
}
