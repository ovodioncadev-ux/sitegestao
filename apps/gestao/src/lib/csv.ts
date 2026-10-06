/**
 * Célula de CSV segura: aspas dobradas e, se começar com = + - @ (ou tab/CR),
 * um apóstrofo na frente. Sem isso, um nome digitado por um visitante vira
 * fórmula quando o dono abre o arquivo no Excel ou no Sheets.
 */
export function celulaCsv(valor: string | null): string {
  const texto = valor ?? '';
  const seguro = /^[=+\-@\t\r]/.test(texto) ? `'${texto}` : texto;
  return `"${seguro.replace(/"/g, '""')}"`;
}
