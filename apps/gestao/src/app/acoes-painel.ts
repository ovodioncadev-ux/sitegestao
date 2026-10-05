'use server';

import { revalidatePath } from 'next/cache';
import { comoDono } from '@/lib/dono';
import { rodar } from '@/lib/erros';
import type { Estado } from '@/lib/tipos';

type Resultado = { reativadas: number; cobrancas_geradas: number; faturas_atrasadas: number; falhas: string[] };

/** O mesmo que o agendador faz, disparado à mão pelo dono. */
export async function rodarRotinaDiaria(): Promise<Estado> {
  return rodar(async () => {
    const linha = await comoDono((bd) =>
      bd.umaLinha<{ r: Resultado }>('select processar_rotina_diaria() as r'),
    );
    const r = linha?.r;
    for (const caminho of ['/', '/assinaturas', '/entregas', '/faturas', '/clientes']) revalidatePath(caminho);
    if (!r) return 'Rotina executada.';
    const falhas = r.falhas.length ? ` ${r.falhas.length} item(ns) não processado(s): ${r.falhas.join('; ')}` : '';
    return `Rotina executada: ${r.reativadas} retorno(s) de pausa, ${r.cobrancas_geradas} cobrança(s) gerada(s), ${r.faturas_atrasadas} fatura(s) marcada(s) como atrasada(s).${falhas}`;
  });
}
