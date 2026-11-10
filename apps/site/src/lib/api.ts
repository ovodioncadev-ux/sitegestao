/**
 * Cliente HTTP da vitrine. Os três endereços são do MESMO domínio do site: em
 * produção o vercel.json manda /conta/* para o app do assinante; no dev local o
 * next.config.ts faz o mesmo com um rewrite. Nada de outro domínio no navegador,
 * nada de CORS.
 */

// O assinante responde em /conta no mesmo domínio (ver vercel.json).
const CONTA = '/conta';

async function pegar<T>(caminho: string): Promise<T> {
  const res = await fetch(`${CONTA}${caminho}`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`${res.status}: ${res.statusText}`);
  const data = (await res.json()) as T & { erro?: string };
  if (data.erro) throw new Error(data.erro);
  return data;
}

export async function buscarPlanos() {
  const data = await pegar<{ planos: PlanoDaApi[] }>('/api/plans');
  return data.planos ?? [];
}

export async function buscarBairros() {
  const data = await pegar<{ bairros: { name: string; isServed: boolean }[] }>('/api/neighborhoods');
  return data.bairros ?? [];
}

export async function cepAtendido(cep: string): Promise<boolean> {
  const digitos = cep.replace(/\D/g, '');
  const data = await pegar<{ atendido: boolean }>(`/api/area?cep=${digitos}`);
  return data.atendido;
}

/** Endereço do passo de assinatura, no app do assinante. O plano vai pelo nome público, nunca por id. */
export function urlAssinar(plano: string): string {
  return `${CONTA}/assinar?plano=${encodeURIComponent(plano)}`;
}

export type PlanoDaApi = {
  frequencia: 'semanal' | 'quinzenal' | 'mensal';
  nome: string;
  intervalDays: number;
  priceCents: number;
  freshnessMaxDays: number;
  freightCents: number;
  firstMonthDiscountPct: number;
  /** Selo do plano, vindo do banco. Nulo = sem selo. */
  badge: string | null;
  features: string[];
};
