/**
 * Redirecionamento depois do login/cadastro.
 *
 * O destino vem da URL (`?proximo=` ou `?voltar=`), então é dado de fora e
 * NUNCA pode mandar a pessoa para outro site (open redirect: um link de
 * "entrar" legítimo que, depois da senha digitada, leva a uma página falsa).
 *
 * Só passa caminho interno, começando com UMA barra. Recusa "//site.com",
 * "/\site.com" (o navegador trata a barra invertida como barra), URL
 * absoluta, "javascript:" e caracteres de controle.
 */
export function caminhoInterno(valor: string | null | undefined, padrao = '/'): string {
  if (!valor || typeof valor !== 'string') return padrao;
  if (valor.length > 300) return padrao;
  if (!valor.startsWith('/') || valor.startsWith('//')) return padrao;
  if (/[\\\u0000-\u001f\u007f]/.test(valor)) return padrao;

  try {
    const base = 'http://interno.invalid';
    const url = new URL(valor, base);
    if (url.origin !== base) return padrao;
  } catch {
    return padrao;
  }
  return valor;
}
