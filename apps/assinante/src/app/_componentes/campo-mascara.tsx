'use client';

import { useState } from 'react';
import { mascararCep, mascararTelefone } from '@/lib/formatar';

/**
 * Input com máscara. O rótulo fica sempre visível acima do campo (não só
 * placeholder). A máscara é conforto: a validação de verdade é do servidor.
 */
export function CampoMascara({
  nome,
  rotulo,
  tipo,
  valorInicial = '',
  placeholder,
  autoComplete,
}: {
  nome: string;
  rotulo: string;
  tipo: 'telefone' | 'cep';
  valorInicial?: string;
  placeholder: string;
  autoComplete?: string;
}) {
  const aplicar = tipo === 'telefone' ? mascararTelefone : mascararCep;
  const [valor, setValor] = useState(aplicar(valorInicial));

  return (
    <label className="campo">
      {rotulo}
      <input
        name={nome}
        type={tipo === 'telefone' ? 'tel' : 'text'}
        inputMode="numeric"
        autoComplete={autoComplete}
        placeholder={placeholder}
        value={valor}
        onChange={(e) => setValor(aplicar(e.target.value))}
        required
      />
    </label>
  );
}
