'use client';

import { useEffect, useState } from 'react';
import { mascararCep } from '@/lib/formatar';

type Situacao = 'nenhuma' | 'consultando' | 'atendido' | 'fora' | 'erro';

/**
 * CEP com aviso na hora: "atendemos" ou "ainda não entregamos aí".
 *
 * É só conforto — quem decide é o banco (`cep_dentro_area_entrega`), de novo,
 * quando o cadastro e a assinatura são gravados. Se a consulta falhar, não
 * bloqueia nada: a pessoa continua e o servidor responde no passo seguinte.
 */
export function CampoCep({ valorInicial = '' }: { valorInicial?: string }) {
  const [valor, setValor] = useState(mascararCep(valorInicial));
  const [situacao, setSituacao] = useState<Situacao>('nenhuma');

  useEffect(() => {
    const digitos = valor.replace(/\D/g, '');
    if (digitos.length !== 8) {
      setSituacao('nenhuma');
      return;
    }

    const controle = new AbortController();
    setSituacao('consultando');
    fetch(`/api/area?cep=${digitos}`, { signal: controle.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((d: { atendido: boolean }) => setSituacao(d.atendido ? 'atendido' : 'fora'))
      .catch((e: unknown) => {
        if (!(e instanceof DOMException && e.name === 'AbortError')) setSituacao('erro');
      });
    return () => controle.abort();
  }, [valor]);

  return (
    <label className="campo">
      CEP
      <input
        name="cep"
        type="text"
        inputMode="numeric"
        autoComplete="postal-code"
        placeholder="30000-000"
        value={valor}
        onChange={(e) => setValor(mascararCep(e.target.value))}
        required
      />
      {situacao === 'consultando' && <span className="msg-info">Conferindo a área de entrega…</span>}
      {situacao === 'atendido' && <span role="status" className="msg-ok">Entregamos neste CEP.</span>}
      {situacao === 'fora' && (
        <span role="status" className="msg-info">
          Ainda não entregamos neste CEP, então não dá para assinar agora. Você pode salvar o cadastro mesmo assim.
        </span>
      )}
      {situacao === 'erro' && (
        <span className="msg-info">Não foi possível conferir a área agora; vamos conferir ao salvar.</span>
      )}
    </label>
  );
}
