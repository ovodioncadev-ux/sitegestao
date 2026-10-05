'use client';

import { useState, type FormEvent } from 'react';
import { useBairros } from '@/hooks/useBairros';
import { cepAtendido } from '@/lib/api';
import { Botao, Secao } from './ui';

export function NeighborhoodSection() {
  const [busca, setBusca] = useState('');
  const { bairros, carregando, erro } = useBairros();
  const [cep, setCep] = useState('');
  const [resultadoCep, setResultadoCep] = useState<string | null>(null);

  async function conferirCep(evento: FormEvent) {
    evento.preventDefault();
    const digitos = cep.replace(/\D/g, '');
    if (digitos.length !== 8) {
      setResultadoCep('Informe um CEP com 8 dígitos.');
      return;
    }
    setResultadoCep('Conferindo…');
    try {
      setResultadoCep((await cepAtendido(digitos)) ? 'Entregamos no seu CEP.' : 'Ainda não entregamos neste CEP.');
    } catch {
      setResultadoCep('Não foi possível conferir agora. Tente de novo em instantes.');
    }
  }

  const bairrosFiltrados = bairros.filter((bairro) =>
    bairro.name.toLowerCase().includes(busca.trim().toLowerCase()),
  );

  return (
    <Secao id="entrega" titulo="Área de entrega">
      <p className="-mt-6 text-center text-suave">
        Frete grátis nos bairros atendidos. Fora dessa área ainda não conseguimos entregar.
      </p>

      <form onSubmit={conferirCep} className="mt-6 text-center">
        <label>
          Seu CEP{' '}
          <input
            type="text"
            inputMode="numeric"
            value={cep}
            onChange={(e) => setCep(e.target.value.replace(/[^\d-]/g, '').slice(0, 9))}
            placeholder="30000-000"
            className="rounded-controle border border-borda px-3 min-h-controle"
          />
        </label>{' '}
        <Botao type="submit" variante="contorno">
          Conferir
        </Botao>
        {resultadoCep && (
          <p role="status" className="mt-2 text-suave">
            {resultadoCep}
          </p>
        )}
      </form>

      <input
        type="text"
        value={busca}
        onChange={(e) => setBusca(e.target.value)}
        placeholder="Digite seu bairro"
        className="rounded-controle border border-borda px-3 min-h-controle mx-auto my-6 block w-full max-w-[360px]"
      />

      {carregando && <p className="text-center">Carregando bairros...</p>}
      {erro && <p className="text-center text-erro">Erro: {erro}</p>}

      {!carregando && !erro && (
        <ul className="mt-6 flex list-none flex-wrap justify-center gap-2 p-0">
          {bairrosFiltrados.length === 0 ? (
            <li className="text-suave">
              {bairros.length === 0
                ? 'A lista de bairros atendidos ainda não foi publicada. Confira pelo seu CEP acima.'
                : 'Nenhum bairro encontrado'}
            </li>
          ) : (
            bairrosFiltrados.map((bairro) => (
              <li
                key={bairro.name}
                className={`rounded-controle px-3 py-1 text-[length:var(--texto-pequeno)] ${
                  bairro.isServed ? 'bg-fundo-alt' : 'bg-borda'
                }`}
              >
                {bairro.name}
              </li>
            ))
          )}
        </ul>
      )}
    </Secao>
  );
}
