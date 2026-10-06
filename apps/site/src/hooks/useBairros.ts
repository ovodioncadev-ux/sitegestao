'use client';

import { useEffect, useState } from 'react';
import { buscarBairros } from '@/lib/api';
import type { Neighborhood } from '@/types';

export function useBairros(inicial?: Neighborhood[] | null) {
  const [bairros, setBairros] = useState<Neighborhood[]>(inicial ?? []);
  const [carregando, setCarregando] = useState(!inicial);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (inicial) return;
    buscarBairros()
      .then((dados) => {
        setBairros(dados || []);
      })
      .catch((err) => {
        console.error('Erro ao carregar bairros:', err);
        setErro(err.message || 'Erro ao carregar bairros');
      })
      .finally(() => setCarregando(false));
  }, [inicial]);

  return { bairros, carregando, erro };
}
