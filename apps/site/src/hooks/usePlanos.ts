'use client';

import { useCallback, useEffect, useState } from 'react';
import { buscarPlanos } from '@/lib/api';
import { mapearPlanos } from '@/lib/mapear';
import type { Plan } from '@/types';

/** `inicial`: planos já buscados no servidor (estão no HTML). Sem ele, busca no navegador. */
export function usePlanos(inicial?: Plan[] | null) {
  const [planos, setPlanos] = useState<Plan[]>(inicial ?? []);
  const [carregando, setCarregando] = useState(!inicial);
  const [erro, setErro] = useState<string | null>(null);

  const [tentativa, setTentativa] = useState(0);
  const recarregar = useCallback(() => {
    setCarregando(true);
    setErro(null);
    setTentativa((n) => n + 1);
  }, []);

  useEffect(() => {
    if (inicial && tentativa === 0) return;
    buscarPlanos()
      .then((dados) => {
        setPlanos(mapearPlanos(dados));
      })
      .catch((err: unknown) => {
        console.error('Erro ao carregar planos:', err);
        setErro('Não foi possível carregar os planos agora. Tente de novo em instantes.');
      })
      .finally(() => setCarregando(false));
  // `inicial` só vale na 1ª carga; não deve refazer a busca ao mudar.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tentativa]);

  return { planos, carregando, erro, recarregar };
}
