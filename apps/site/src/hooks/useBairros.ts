'use client';

import { useCallback, useEffect, useState } from 'react';
import { buscarBairros } from '@/lib/api';
import type { Neighborhood } from '@/types';

export function useBairros() {
  const [bairros, setBairros] = useState<Neighborhood[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = useCallback(() => {
    setCarregando(true);
    setErro(null);
    buscarBairros()
      .then((dados) => {
        setBairros(dados || []);
      })
      .catch((err: unknown) => {
        console.error('Erro ao carregar bairros:', err);
        // Mensagem fixa: o detalhe técnico fica só no console.
        setErro('Não foi possível carregar a lista de bairros agora.');
      })
      .finally(() => setCarregando(false));
  }, []);

  useEffect(() => {
    carregar();
  }, [carregar]);

  return { bairros, carregando, erro, recarregar: carregar };
}
