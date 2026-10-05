'use server';

import { revalidatePath } from 'next/cache';
import { comoDono } from '@/lib/dono';
import { ErroNegocio, rodar } from '@/lib/erros';
import type { Estado } from '@/lib/tipos';
import { CHAVES_STATUS_CLIENTE } from '@/lib/rotulos';
import {
  campo,
  cepOpcional,
  emailOpcional,
  escolha,
  inteiroOpcional,
  telefoneOpcional,
  textoObrigatorio,
  textoOpcional,
  ufOpcional,
  uuid,
} from '@/lib/validacao';

/**
 * Nada de `update(formData)` direto: os campos abaixo são exatamente os que
 * este formulário aceita. `usuario_id`, `dentro_area_entrega`, `indicado_por`,
 * `codigo_indicacao` e `origem` não estão aqui de propósito e não têm como
 * chegar por esta porta, mesmo que alguém edite o HTML.
 *
 * Toda escrita passa por comoDono(): confere o papel de dono no servidor e só
 * então abre a conexão administrativa (nenhum grant de escrita em `clientes`
 * existe para app_usuario, nem para o dono).
 */

function lerCliente(dados: FormData) {
  return {
    nome: textoObrigatorio(campo(dados, 'nome'), 'Nome', 120),
    email: emailOpcional(campo(dados, 'email')),
    telefone: telefoneOpcional(campo(dados, 'telefone')),
    cep: cepOpcional(campo(dados, 'cep')),
    endereco: textoOpcional(campo(dados, 'endereco'), 'Endereço', 200),
    numero: textoOpcional(campo(dados, 'numero'), 'Número', 20),
    complemento: textoOpcional(campo(dados, 'complemento'), 'Complemento', 100),
    bairro: textoOpcional(campo(dados, 'bairro'), 'Bairro', 100),
    cidade: textoOpcional(campo(dados, 'cidade'), 'Cidade', 100),
    estado: ufOpcional(campo(dados, 'estado')),
    status: escolha(campo(dados, 'status') || 'cadastro_andamento', CHAVES_STATUS_CLIENTE, 'Status'),
    frequencia: campo(dados, 'frequencia'),
    pentes: inteiroOpcional(campo(dados, 'pentes_padrao'), 'Pentes por entrega', 1, 50),
    duzias: inteiroOpcional(campo(dados, 'duzias_padrao'), 'Dúzias por entrega', 0, 50),
    semDesconto: dados.get('sem_desconto') === 'on',
  };
}

function avisoDeArea(cep: string | null, dentro: boolean): string {
  if (!cep) return '';
  return dentro ? ' CEP dentro da área de entrega.' : ' CEP fora da área de entrega.';
}

export async function criarCliente(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const c = lerCliente(dados);

    const criado = await comoDono(async (bd) => {
      let planoId: number | null = null;
      if (c.frequencia) {
        const plano = await bd.umaLinha<{ id: number }>(
          'select id from planos where frequencia::text = $1',
          [c.frequencia],
        );
        if (!plano) throw new ErroNegocio('Plano inválido.');
        planoId = plano.id;
      }

      return bd.umaLinha<{ dentro_area_entrega: boolean }>(
        `insert into clientes
           (nome, email, telefone, cep, endereco, numero, complemento, bairro, cidade, estado,
            status, plano_id, pentes_padrao, duzias_padrao, origem, desconto_primeiro_mes_aplicavel)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,'organico',$15)
         returning dentro_area_entrega`,
        [c.nome, c.email, c.telefone, c.cep, c.endereco, c.numero, c.complemento, c.bairro,
         c.cidade, c.estado, c.status, planoId, c.pentes, c.duzias, !c.semDesconto],
      );
    });

    revalidatePath('/clientes');
    return `Cliente cadastrado.${avisoDeArea(c.cep, Boolean(criado?.dentro_area_entrega))}`;
  });
}

export async function atualizarCliente(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = uuid(campo(dados, 'id'), 'Cliente');
    const c = lerCliente(dados);

    const salvo = await comoDono(async (bd) => {
      let planoId: number | null = null;
      if (c.frequencia) {
        const plano = await bd.umaLinha<{ id: number }>(
          'select id from planos where frequencia::text = $1',
          [c.frequencia],
        );
        if (!plano) throw new ErroNegocio('Plano inválido.');
        planoId = plano.id;
      }

      return bd.umaLinha<{ dentro_area_entrega: boolean }>(
        `update clientes
            set nome = $2, email = $3, telefone = $4, cep = $5, endereco = $6, numero = $7,
                complemento = $8, bairro = $9, cidade = $10, estado = $11, status = $12,
                -- Com assinatura vigente, o plano é da assinatura: esta tela não o troca.
                plano_id = case
                             when exists (select 1 from assinaturas a
                                           where a.cliente_id = $1 and a.status in ('ativa', 'pausada'))
                             then plano_id
                             else $13::smallint
                           end,
                pentes_padrao = $14, duzias_padrao = $15,
                desconto_primeiro_mes_aplicavel = $16
          where id = $1
          returning dentro_area_entrega`,
        [id, c.nome, c.email, c.telefone, c.cep, c.endereco, c.numero, c.complemento, c.bairro,
         c.cidade, c.estado, c.status, planoId, c.pentes, c.duzias, !c.semDesconto],
      );
    });

    // UPDATE que não encontrou linha não dá erro no SQL: sem esta conferência,
    // "salvar" num id que sumiu pareceria ter funcionado.
    if (!salvo) throw new ErroNegocio('Cliente não encontrado.');

    revalidatePath('/clientes');
    revalidatePath(`/clientes/${id}`);
    return `Cliente atualizado.${avisoDeArea(c.cep, salvo.dentro_area_entrega)}`;
  });
}

/**
 * Vínculo manual conta ↔ cliente. É o caminho para cliente que o dono
 * cadastrou antes de a pessoa ter conta: o vínculo automático por e-mail só
 * acontece com e-mail CONFIRMADO, e enquanto não houver serviço de e-mail
 * ninguém tem e-mail confirmado. Aqui o dono, que conhece a pessoa, assume
 * a conferência — e ela fica na auditoria (`conta_vinculada`).
 */
export async function vincularConta(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = uuid(campo(dados, 'id'), 'Cliente');
    const email = emailOpcional(campo(dados, 'email_conta'));
    if (!email) throw new ErroNegocio('Informe o e-mail da conta.');

    await comoDono(async (bd) => {
      const conta = await bd.umaLinha<{ id: string; papel: string }>(
        `select u.id, p.papel::text from "user" u join perfis p on p.id = u.id where lower(u.email) = lower($1)`,
        [email],
      );
      if (!conta) throw new ErroNegocio('Não existe conta com esse e-mail.');
      if (conta.papel !== 'assinante') throw new ErroNegocio('Só conta de assinante pode ser vinculada.');

      const ocupada = await bd.umaLinha<{ id: string }>('select id from clientes where usuario_id = $1', [conta.id]);
      if (ocupada) throw new ErroNegocio('Essa conta já está vinculada a outro cliente.');

      const atualizado = await bd.umaLinha<{ id: string }>(
        'update clientes set usuario_id = $2 where id = $1 and usuario_id is null returning id',
        [id, conta.id],
      );
      if (!atualizado) throw new ErroNegocio('Este cliente já tem uma conta vinculada.');
    });

    revalidatePath(`/clientes/${id}`);
    return 'Conta vinculada.';
  });
}

export async function desvincularConta(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = uuid(campo(dados, 'id'), 'Cliente');
    const atualizado = await comoDono((bd) =>
      bd.umaLinha<{ id: string }>(
        'update clientes set usuario_id = null where id = $1 and usuario_id is not null returning id',
        [id],
      ),
    );
    if (!atualizado) throw new ErroNegocio('Este cliente não tem conta vinculada.');

    revalidatePath(`/clientes/${id}`);
    return 'Conta desvinculada.';
  });
}
