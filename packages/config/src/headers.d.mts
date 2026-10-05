export type Opcoes = {
  modoRelatorio?: boolean;
};

export function cabecalhosDeSeguranca(opcoes?: Opcoes): { key: string; value: string }[];
