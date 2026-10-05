'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { comoAssinante } from '@/lib/assinante';
import { ErroNegocio, rodar } from '@/lib/erros';
import { ehFrequencia } from '@/lib/planos';
import type { Estado } from '@/lib/tipos';
import {
  campo,
  cepObrigatorio,
  telefoneObrigatorio,
  textoObrigatorio,
  textoOpcional,
  ufObrigatoria,
} from '@/lib/validacao';

/**
 * Os dois passos que gravam algo no fluxo de assinatura pelo site.
 *
 * Nenhum dos dois recebe id de cliente, e-mail, status, preço ou data: o
 * cliente é o da sessão, o e-mail é o da conta, o status e a data são
 * decididos pelas funções do banco (`criar_meu_cadastro` e `assinar_plano`),
 * que conferem tudo de novo. O que chega do formulário é só o que a pessoa
 * digitou e o identificador público do plano (semanal | quinzenal | mensal).
 */

function frequenciaDoFormulario(dados: FormData) {
  const plano = campo(dados, 'plano');
  if (!ehFrequencia(plano)) throw new ErroNegocio('Plano inválido. Escolha um plano de novo.');
  return plano;
}

export async function criarMeuCadastro(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const plano = frequenciaDoFormulario(dados);

    // Sem fallback: campo vazio bloqueia. O banco valida de novo.
    const nome = textoObrigatorio(campo(dados, 'nome'), 'Nome', 3, 120);
    const telefone = telefoneObrigatorio(campo(dados, 'telefone'));
    const cep = cepObrigatorio(campo(dados, 'cep'));
    const endereco = textoObrigatorio(campo(dados, 'endereco'), 'Rua', 2, 200);
    const numero = textoObrigatorio(campo(dados, 'numero'), 'Número', 1, 20);
    const complemento = textoOpcional(campo(dados, 'complemento'), 'Complemento', 100);
    const bairro = textoObrigatorio(campo(dados, 'bairro'), 'Bairro', 2, 100);
    const cidade = textoObrigatorio(campo(dados, 'cidade'), 'Cidade', 2, 100);
    const estado = ufObrigatoria(campo(dados, 'estado'));

    await comoAssinante((bd) =>
      bd.consultar('select criar_meu_cadastro($1, $2, $3, $4, $5, $6, $7, $8, $9)', [
        nome,
        telefone,
        cep,
        endereco,
        numero,
        complemento,
        bairro,
        cidade,
        estado,
      ]),
    );

    revalidatePath('/assinar');
    redirect(`/assinar?plano=${plano}`);
  });
}

export async function confirmarAssinatura(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const plano = frequenciaDoFormulario(dados);

    await comoAssinante(async (bd) => {
      const linha = await bd.umaLinha<{ id: number }>(
        'select id from planos where frequencia = $1::frequencia_plano and ativo',
        [plano],
      );
      if (!linha) throw new ErroNegocio('Este plano não está disponível.');

      await bd.consultar('select assinar_plano($1::smallint)', [linha.id]);
    });

    revalidatePath('/');
    revalidatePath('/assinar');
    redirect('/?nova=1');
  });
}
