'use client';

import { useEffect, useState } from 'react';
import { buscarConteudo } from '@/lib/api';
import type { ConteudoSite } from '@/types';

export function useConteudoSite(inicial?: ConteudoSite | null) {
  const [conteudo, setConteudo] = useState<ConteudoSite | null>(inicial ?? null);
  const [carregando, setCarregando] = useState(!inicial);
  const [erro, setErro] = useState(false);

  useEffect(() => {
    if (inicial) return;
    buscarConteudo()
      .then(setConteudo)
      .catch((err: unknown) => {
        console.error('Erro ao carregar conteúdo do site:', err);
        setErro(true);
      })
      .finally(() => setCarregando(false));
  }, [inicial]);

  return { conteudo, carregando, erro };
}
