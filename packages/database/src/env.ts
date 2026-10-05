/**
 * Leitura de variáveis de ambiente com erro legível.
 *
 * Sem isto, uma variável faltando vira "undefined" silencioso e o app só
 * quebra lá na frente, num lugar que não tem nada a ver com a causa.
 */

export function exigirEnv(nome: string): string {
  const valor = process.env[nome];
  if (!valor || valor.trim() === '') {
    throw new Error(
      `Variável de ambiente ausente: ${nome}. ` +
        `Confira o .env.example na raiz do monorepo e preencha o seu .env.`,
    );
  }
  return valor;
}

/** Devolve a variável ou undefined, sem estourar. Para o que é opcional. */
export function envOpcional(nome: string): string | undefined {
  const valor = process.env[nome];
  return valor && valor.trim() !== '' ? valor : undefined;
}
