import type { Plan } from '@/types';

export function formatarReais(centavos: number): string {
  return (centavos / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });
}

export function textoFrescor(plan: Plan): string {
  return `Máx. ${plan.freshnessMaxDays} dias entre a colheita e a entrega`;
}

export function textoFrete(plan: Plan): string {
  return plan.freightCents === 0
    ? 'Frete grátis'
    : `Frete: ${formatarReais(plan.freightCents)}`;
}

export function textoDesconto(plan: Plan): string {
  return `${plan.firstMonthDiscountPct}% de desconto no 1º mês (cartão ou PIX)`;
}

/** Resumo dos planos para textos gerais (hero, FAQ, comparativo): sempre derivado, nunca escrito na mão. */
export function resumoPlanos(planos: Plan[]) {
  return {
    freshnessMaxDays: Math.max(...planos.map((p) => p.freshnessMaxDays)),
    freteGratis: planos.every((p) => p.freightCents === 0),
    firstMonthDiscountPct: Math.max(...planos.map((p) => p.firstMonthDiscountPct)),
  };
}

export function precoComDesconto(plan: Plan): number {
  return Math.round(plan.priceCents * (1 - plan.firstMonthDiscountPct / 100));
}

export function somenteDigitos(valor: string): string {
  return valor.replace(/\D/g, '');
}

export function mascararTelefone(valor: string): string {
  const digitos = somenteDigitos(valor).slice(0, 11);
  if (digitos.length <= 2) return digitos;
  if (digitos.length <= 6) return `(${digitos.slice(0, 2)}) ${digitos.slice(2)}`;
  if (digitos.length <= 10) {
    return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 6)}-${digitos.slice(6)}`;
  }
  return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 7)}-${digitos.slice(7)}`;
}

export function telefoneValido(valor: string): boolean {
  const digitos = somenteDigitos(valor);
  return digitos.length === 10 || digitos.length === 11;
}
