/**
 * Cliente HTTP da vitrine. Os três endereços são do PRÓPRIO site: o
 * next.config.ts os repassa ao app do assinante no servidor (rewrites).
 * Nada de URL de outro domínio no navegador, nada de cookie, nada de CORS.
 */

async function pegar<T>(caminho: string): Promise<T> {
  const res = await fetch(caminho, { cache: 'no-store' });
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
  const base = process.env.NEXT_PUBLIC_URL_ASSINANTE ?? 'http://localhost:3001';
  return `${base}/assinar?plano=${encodeURIComponent(plano)}`;
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
