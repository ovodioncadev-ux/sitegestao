export type PlanId = 'mensal' | 'quinzenal' | 'semanal';

export type Plan = {
  id: PlanId;
  name: string;
  intervalDays: number;
  priceCents: number;
  /** Dias entre a colheita e a entrega. Decisão do Fred: 7 dias em todos os planos. */
  freshnessMaxDays: number;
  /** Decisão do Fred: frete grátis para todos os planos, dentro da área atendida. */
  freightCents: number;
  /** Decisão do Fred: 10% no 1º mês, vale cartão e PIX, todos os planos. */
  firstMonthDiscountPct: number;
  /** Entregas previstas por mês e preço de UMA entrega (D10). */
  deliveriesPerMonth: number;
  deliveryPriceCents: number;
  features: string[];
  highlighted: boolean;
  badge?: string;
};

export type Neighborhood = {
  name: string;
  isServed: boolean;
};

export type ComparisonRow = {
  feature: string;
  ovoDiOnca: string;
  supermarket: string;
};

export type FaqItem = {
  question: string;
  answer: string;
};

/** Texto de vitrine que o banco sabe afirmar. Nulo/falso = o site não afirma. */
export type ConteudoSite = {
  freshnessMaxDays: number | null;
  freeShipping: boolean;
  firstMonthDiscountPct: number | null;
  cutoff: { weekday: number; time: string } | null;
  faq: FaqItem[];
};
