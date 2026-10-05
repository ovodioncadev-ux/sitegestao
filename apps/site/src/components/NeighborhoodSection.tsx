'use client';

import { useState, type FormEvent } from 'react';
import { useBairros } from '@/hooks/useBairros';
import { cepAtendido } from '@/lib/api';

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
    <section
      id="entrega"
      style={{ maxWidth: 'var(--largura-conteudo)', margin: '0 auto', padding: `var(--esp-16) var(--esp-6)` }}
    >
      <h2 style={{ textAlign: 'center', fontSize: 'var(--texto-titulo)' }}>Área de entrega</h2>
      <p style={{ textAlign: 'center', color: 'var(--cor-texto-suave)', marginTop: 'var(--esp-2)' }}>
        Frete grátis nos bairros atendidos. Fora dessa área ainda não conseguimos entregar.
      </p>

      <form onSubmit={conferirCep} style={{ textAlign: 'center', marginTop: 'var(--esp-6)' }}>
        <label>
          Seu CEP{' '}
          <input
            type="text"
            inputMode="numeric"
            value={cep}
            onChange={(e) => setCep(e.target.value.replace(/[^\d-]/g, '').slice(0, 9))}
            placeholder="30000-000"
            style={{
              minHeight: 'var(--altura-controle)',
              borderRadius: 'var(--raio-controle)',
              border: '1px solid var(--cor-borda)',
              padding: `0 var(--esp-3)`,
            }}
          />
        </label>{' '}
        <button
          type="submit"
          style={{
            minHeight: 'var(--altura-controle)',
            borderRadius: 'var(--raio-controle)',
            border: '1px solid var(--cor-ouro)',
            background: 'transparent',
            color: 'var(--cor-ouro-escuro)',
            padding: `0 var(--esp-4)`,
          }}
        >
          Conferir
        </button>
        {resultadoCep && (
          <p role="status" style={{ marginTop: 'var(--esp-2)', color: 'var(--cor-texto-suave)' }}>
            {resultadoCep}
          </p>
        )}
      </form>

      <input
        type="text"
        value={busca}
        onChange={(e) => setBusca(e.target.value)}
        placeholder="Digite seu bairro"
        style={{
          display: 'block',
          margin: 'var(--esp-6) auto',
          width: '100%',
          maxWidth: '360px',
          minHeight: 'var(--altura-controle)',
          borderRadius: 'var(--raio-controle)',
          border: '1px solid var(--cor-borda)',
          padding: `0 var(--esp-3)`,
        }}
      />

      {carregando && <p style={{ textAlign: 'center' }}>Carregando bairros...</p>}
      {erro && <p style={{ textAlign: 'center', color: 'var(--cor-erro)' }}>Erro: {erro}</p>}

      {!carregando && !erro && (
        <ul
          style={{
            listStyle: 'none',
            padding: 0,
            display: 'flex',
            flexWrap: 'wrap',
            gap: 'var(--esp-2)',
            justifyContent: 'center',
            marginTop: 'var(--esp-6)',
          }}
        >
          {bairrosFiltrados.length === 0 ? (
            <li style={{ color: 'var(--cor-texto-suave)' }}>
              {bairros.length === 0
                ? 'A lista de bairros atendidos ainda não foi publicada. Confira pelo seu CEP acima.'
                : 'Nenhum bairro encontrado'}
            </li>
          ) : (
            bairrosFiltrados.map((bairro) => (
              <li
                key={bairro.name}
                style={{
                  background: bairro.isServed ? 'var(--cor-fundo-alt)' : 'var(--cor-borda)',
                  borderRadius: 'var(--raio-controle)',
                  padding: `var(--esp-1) var(--esp-3)`,
                  fontSize: 'var(--texto-pequeno)',
                }}
              >
                {bairro.name}
              </li>
            ))
          )}
        </ul>
      )}
    </section>
  );
}
