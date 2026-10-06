import type { PlanoDaApi } from './api';
import { mapearPlanos } from './mapear';
import type { ConteudoSite, Neighborhood, Plan } from '../types';


export type DadosDoSite = {
  planos: Plan[] | null;
  conteudo: ConteudoSite | null;
  bairros: Neighborhood[] | null;
};

/**
 * Busca, NO SERVIDOR, o que a página mostra (planos, conteúdo, bairros), para que
 * esteja no HTML que o buscador recebe — e não só depois do JavaScript rodar.
 *
 * Cada leitura é independente e tem prazo curto: se uma falhar, vira `null` e o
 * componente correspondente cai na busca pelo navegador (comportamento anterior).
 * O cache de 30 s casa com o do próprio app do assinante (as rotas já têm 30 s).
 */
export async function buscarDadosDoSite(): Promise<DadosDoSite> {
  const base = (process.env.NEXT_PUBLIC_URL_ASSINANTE ?? 'http://localhost:3001').replace(/\/$/, '');

  async function ler<T>(caminho: string): Promise<T | null> {
    try {
      const res = await fetch(`${base}${caminho}`, { next: { revalidate: 30 }, signal: AbortSignal.timeout(4000) });
      if (!res.ok) return null;
      const corpo = (await res.json()) as T & { erro?: string };
      return corpo.erro ? null : corpo;
    } catch {
      return null;
    }
  }

  const [planos, conteudo, bairros] = await Promise.all([
    ler<{ planos: PlanoDaApi[] }>('/api/plans'),
    ler<ConteudoSite>('/api/site'),
    ler<{ bairros: Neighborhood[] }>('/api/neighborhoods'),
  ]);

  return {
    planos: planos?.planos ? mapearPlanos(planos.planos) : null,
    conteudo: conteudo && Array.isArray(conteudo.faq) ? conteudo : null,
    bairros: bairros?.bairros ?? null,
  };
}
