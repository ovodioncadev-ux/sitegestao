import Link from 'next/link';
import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { FormAcao } from '../../_componentes/form-acao';
import { Pagina, SemPermissao } from '../../_componentes/pagina';
import { CamposCliente } from '../campos-cliente';
import { criarCliente } from '../acoes';

export default async function NovoCliente() {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const planos = await comoUsuario(autorizacao.usuario.usuarioId, (bd) =>
    bd.consultar<{ frequencia: string; nome: string }>(
      'select frequencia::text, nome from planos where ativo order by intervalo_dias',
    ),
  );

  return (
    <Pagina titulo="Novo cliente">
      <p>
        <Link href="/clientes">← Clientes</Link>
      </p>
      <FormAcao acao={criarCliente} rotulo="Cadastrar cliente" limpar>
        <CamposCliente planos={planos} />
      </FormAcao>
    </Pagina>
  );
}
