'use client';

import { useEffect, useState } from 'react';
import { buscarBairros } from '@/lib/api';
import type { Neighborhood } from '@/types';

export function useBairros() {
  const [bairros, setBairros] = useState<Neighborhood[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    buscarBairros()
      .then((dados) => {
        setBairros(dados || []);
      })
      .catch((err) => {
        console.error('Erro ao carregar bairros:', err);
        setErro(err.message || 'Erro ao carregar bairros');
      })
      .finally(() => setCarregando(false));
  }, []);

  return { bairros, carregando, erro };
}
