'use client';

import { useCallback, useEffect, useState } from 'react';
import { buscarPlanos } from '@/lib/api';
import type { Plan } from '@/types';

export function usePlanos() {
  const [planos, setPlanos] = useState<Plan[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);

  const [tentativa, setTentativa] = useState(0);
  const recarregar = useCallback(() => {
    setCarregando(true);
    setErro(null);
    setTentativa((n) => n + 1);
  }, []);

  useEffect(() => {
    buscarPlanos()
      .then((dados) => {
        setPlanos(
          dados.map((p) => ({
            id: p.frequencia,
            name: p.nome,
            intervalDays: p.intervalDays,
            priceCents: p.priceCents,
            freshnessMaxDays: p.freshnessMaxDays,
            freightCents: p.freightCents,
            firstMonthDiscountPct: p.firstMonthDiscountPct,
            features: p.features,
            // O selo e o destaque vêm do banco (planos.selo), não do nome do plano.
            highlighted: Boolean(p.badge),
            badge: p.badge ?? undefined,
          })),
        );
      })
      .catch((err: unknown) => {
        console.error('Erro ao carregar planos:', err);
        setErro('Não foi possível carregar os planos agora. Tente de novo em instantes.');
      })
      .finally(() => setCarregando(false));
  }, [tentativa]);

  return { planos, carregando, erro, recarregar };
}
