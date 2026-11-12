'use client';

import { FormAcao, type Confirmacao } from './form-acao';
import type { ComponentProps } from 'react';

/**
 * Ação que desfaz algo (cancelar, remover, desvincular, recusar): botão de
 * perigo + diálogo com o nome do registro. É o FormAcao com `confirmar`.
 */
export function ConfirmarAcao({
  confirmar,
  variante = 'perigo',
  ...resto
}: Omit<ComponentProps<typeof FormAcao>, 'confirmar' | 'variante'> & {
  confirmar: Confirmacao;
  variante?: ComponentProps<typeof FormAcao>['variante'];
}) {
  return <FormAcao variante={variante} confirmar={confirmar} {...resto} />;
}
