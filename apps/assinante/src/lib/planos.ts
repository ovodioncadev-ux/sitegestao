import type { Executor } from '@ovo/database';

/** Identificador público do plano na URL: o mesmo valor do enum `frequencia_plano`. Nunca o id numérico. */
export const FREQUENCIAS = ['semanal', 'quinzenal', 'mensal'] as const;
export type Frequencia = (typeof FREQUENCIAS)[number];

export type PlanoPublico = {
  id: number;
  frequencia: Frequencia;
  nome: string;
  intervaloDias: number;
  ancorarEmQuarta: boolean;
  precoCentavos: number;
  freshnessMaxDias: number;
  freteCentavos: number;
  descontoPrimeiroMesPct: number;
  /** Selo do cartão do plano (ex.: "Recomendado"). Vem do banco (`planos.selo`); nulo = sem selo. */
  selo: string | null;
};

export function ehFrequencia(valor: unknown): valor is Frequencia {
  return typeof valor === 'string' && (FREQUENCIAS as readonly string[]).includes(valor);
}

type LinhaPlano = {
  id: number;
  frequencia: Frequencia;
  nome: string;
  intervalo_dias: number;
  ancorar_em_quarta: boolean;
  preco_centavos: number;
  freshness_max_dias: number;
  frete_centavos: number;
  desconto_primeiro_mes_pct: string;
  selo: string | null;
};

/**
 * Vitrine de planos. O preço é derivado NO BANCO por `planos_publicos()`
 * (preço do pente × entregas por mês): nada de valor escrito no código.
 */
export async function lerPlanosPublicos(bd: Executor): Promise<PlanoPublico[]> {
  const linhas = await bd.consultar<LinhaPlano>('select * from planos_publicos()');
  return linhas.map((p) => ({
    id: p.id,
    frequencia: p.frequencia,
    nome: p.nome,
    intervaloDias: p.intervalo_dias,
    ancorarEmQuarta: p.ancorar_em_quarta,
    precoCentavos: p.preco_centavos,
    freshnessMaxDias: p.freshness_max_dias,
    freteCentavos: p.frete_centavos,
    descontoPrimeiroMesPct: Number(p.desconto_primeiro_mes_pct),
    selo: p.selo,
  }));
}
