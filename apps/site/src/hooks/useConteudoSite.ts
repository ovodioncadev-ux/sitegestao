'use client';

import { useEffect, useState } from 'react';
import { buscarConteudo } from '@/lib/api';
import type { ConteudoSite } from '@/types';

export function useConteudoSite() {
  const [conteudo, setConteudo] = useState<ConteudoSite | null>(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(false);

  useEffect(() => {
    buscarConteudo()
      .then(setConteudo)
      .catch((err: unknown) => {
        console.error('Erro ao carregar conteúdo do site:', err);
        setErro(true);
      })
      .finally(() => setCarregando(false));
  }, []);

  return { conteudo, carregando, erro };
}
