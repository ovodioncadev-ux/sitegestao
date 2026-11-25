'use client';

import { useState, type FormEvent } from 'react';
import { useBairros } from '@/hooks/useBairros';
import { cepAtendido } from '@/lib/api';

/** Só dígitos, no máximo 8, com hífen depois do quinto: "30130000" -> "30130-000". */
function mascararCep(valor: string): string {
  const digitos = valor.replace(/\D/g, '').slice(0, 8);
  return digitos.length > 5 ? `${digitos.slice(0, 5)}-${digitos.slice(5)}` : digitos;
}

export function NeighborhoodSection() {
  const [busca, setBusca] = useState('');
  const { bairros, carregando, erro, recarregar } = useBairros();
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

      <form
        onSubmit={conferirCep}
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          alignItems: 'flex-end',
          justifyContent: 'center',
          gap: 'var(--esp-3)',
          marginTop: 'var(--esp-6)',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--esp-1)', textAlign: 'left' }}>
          <label htmlFor="campo-cep" style={{ fontSize: 'var(--texto-pequeno)' }}>
            Seu CEP
          </label>
          <input
            id="campo-cep"
            className="campo-texto"
            type="text"
            inputMode="numeric"
            autoComplete="postal-code"
            maxLength={9}
            value={cep}
            onChange={(e) => setCep(mascararCep(e.target.value))}
            placeholder="30000-000"
            aria-describedby="resultado-cep"
          />
        </div>
        <button type="submit" className="botao-contorno">
          Conferir
        </button>
        <p
          id="resultado-cep"
          role="status"
          style={{
            flexBasis: '100%',
            textAlign: 'center',
            margin: 0,
            minHeight: '1.6em',
            color: 'var(--cor-texto-suave)',
          }}
        >
          {resultadoCep}
        </p>
      </form>

      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 'var(--esp-1)', marginTop: 'var(--esp-6)' }}>
        <label htmlFor="campo-bairro" style={{ fontSize: 'var(--texto-pequeno)' }}>
          Buscar bairro
        </label>
        <input
          id="campo-bairro"
          className="campo-texto"
          type="search"
          value={busca}
          onChange={(e) => setBusca(e.target.value)}
          placeholder="Digite seu bairro"
          style={{ width: '100%', maxWidth: '360px' }}
        />
      </div>

      {carregando && (
        <p role="status" style={{ textAlign: 'center', marginTop: 'var(--esp-6)' }}>
          Carregando bairros...
        </p>
      )}
      {erro && (
        <div role="alert" style={{ textAlign: 'center', marginTop: 'var(--esp-6)' }}>
          <p style={{ color: 'var(--cor-erro)' }}>{erro}</p>
          <button type="button" className="botao-contorno" onClick={recarregar} style={{ marginTop: 'var(--esp-3)' }}>
            Tentar de novo
          </button>
        </div>
      )}

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
