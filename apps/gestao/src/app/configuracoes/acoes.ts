'use server';

import { revalidatePath } from 'next/cache';
import { comoDono } from '@/lib/dono';
import { ErroNegocio, rodar } from '@/lib/erros';
import type { Estado } from '@/lib/tipos';
import { campo, decimal, idNumerico, inteiro, reaisParaCentavos, textoObrigatorio, textoOpcional } from '@/lib/validacao';

/**
 * Lista fechada de campos, como em clientes: nada de `update(formData)`.
 * A auditoria registra antes/depois (`configuracao_alterada`, `plano_alterado`).
 */

function atualizarTelas() {
  for (const caminho of ['/configuracoes', '/', '/assinaturas']) revalidatePath(caminho);
}

const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;

export async function salvarConfiguracao(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const precoPente = reaisParaCentavos(campo(dados, 'preco_pente'), 'Preço do pente');
    const precoDuzia = reaisParaCentavos(campo(dados, 'preco_duzia'), 'Preço da dúzia', true);
    const diaCorte = inteiro(campo(dados, 'dia_corte'), 'Dia do corte', 0, 6);
    const horaCorte = campo(dados, 'hora_corte');
    if (!HORA.test(horaCorte)) throw new ErroNegocio('Hora do corte inválida. Use HH:MM.');
    const bonus = decimal(campo(dados, 'bonus_indicador_pct'), 'Bônus do indicador (%)', 0, 100);
    const teto = decimal(campo(dados, 'teto_credito_indicacao_pct'), 'Teto de crédito por indicação (%)', 0, 100);

    await comoDono((bd) =>
      bd.consultar(
        `update config_negocio
            set preco_pente_centavos = $1, preco_duzia_centavos = $2, dia_corte = $3,
                hora_corte = $4::time, bonus_indicador_pct = $5, teto_credito_indicacao_pct = $6,
                atualizado_em = now()
          where id = 1`,
        [precoPente, precoDuzia, diaCorte, horaCorte, bonus, teto],
      ),
    );

    atualizarTelas();
    return 'Configuração salva. Os valores novos valem para as próximas cobranças; faturas já criadas não mudam.';
  });
}

export async function salvarPlano(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Plano');
    const nome = textoObrigatorio(campo(dados, 'nome'), 'Nome', 60);
    const intervalo = inteiro(campo(dados, 'intervalo_dias'), 'Intervalo (dias)', 1, 90);
    const entregasPorMes = inteiro(campo(dados, 'entregas_por_mes'), 'Entregas por mês', 1, 31);
    const frescor = inteiro(campo(dados, 'freshness_max_dias'), 'Frescor máximo (dias)', 1, 60);
    const frete = reaisParaCentavos(campo(dados, 'frete'), 'Frete', true);
    const desconto = decimal(campo(dados, 'desconto_primeiro_mes_pct'), 'Desconto do 1º mês (%)', 0, 100);
    const selo = textoOpcional(campo(dados, 'selo'), 'Selo', 30);
    const ancorar = dados.get('ancorar_em_quarta') === 'on';
    const ativo = dados.get('ativo') === 'on';

    const salvo = await comoDono(async (bd) => {
      if (!ativo) {
        const uso = await bd.umaLinha<{ n: string }>(
          `select count(*) as n from assinaturas where plano_id = $1 and status in ('ativa', 'pausada')`,
          [id],
        );
        if (Number(uso?.n ?? 0) > 0) {
          throw new ErroNegocio('Este plano tem assinaturas ativas ou pausadas: troque o plano delas antes de desativá-lo.');
        }
      }
      return bd.umaLinha<{ id: number }>(
        `update planos
            set nome = $2, intervalo_dias = $3, entregas_por_mes = $4, freshness_max_dias = $5,
                frete_centavos = $6, desconto_primeiro_mes_pct = $7, ancorar_em_quarta = $8, ativo = $9,
                selo = $10
          where id = $1
          returning id`,
        [id, nome, intervalo, entregasPorMes, frescor, frete, desconto, ancorar, ativo, selo],
      );
    });
    if (!salvo) throw new ErroNegocio('Plano não encontrado.');

    atualizarTelas();
    return `Plano ${nome} salvo.`;
  });
}
