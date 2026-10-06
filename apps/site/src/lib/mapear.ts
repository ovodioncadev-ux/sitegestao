import type { PlanoDaApi } from './api';
import type { Plan } from '../types';

/** Resposta de /api/plans → o que a vitrine mostra. Usado no servidor (SSR) e no navegador (reserva). */
export function mapearPlanos(dados: PlanoDaApi[]): Plan[] {
  return dados.map((p) => ({
    id: p.frequencia,
    name: p.nome,
    intervalDays: p.intervalDays,
    priceCents: p.priceCents,
    freshnessMaxDays: p.freshnessMaxDays,
    freightCents: p.freightCents,
    firstMonthDiscountPct: p.firstMonthDiscountPct,
    deliveriesPerMonth: p.deliveriesPerMonth,
    deliveryPriceCents: p.deliveryPriceCents,
    features: p.features,
    // O selo e o destaque vêm do banco (planos.selo), não do nome do plano.
    highlighted: Boolean(p.badge),
    badge: p.badge ?? undefined,
  }));
}
