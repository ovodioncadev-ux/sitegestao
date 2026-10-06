/**
 * Dados de SEO do site. Funções puras, sem dependência de alias nem de React, para
 * poderem ser testadas com `node --test`.
 */

export const NOME_DO_SITE = 'Ovo di Onça';

/** Endereço público do site (o canonical, o sitemap e o Open Graph partem dele). Lido no BUILD. */
export function urlDoSite(env: Record<string, string | undefined> = process.env): string {
  return (env.NEXT_PUBLIC_URL_SITE ?? 'http://localhost:3002').replace(/\/$/, '');
}

/**
 * Serializa dados estruturados para dentro de um <script type="application/ld+json">.
 * O conteúdo inclui texto que o DONO edita no painel (FAQ): se ele contivesse
 * `</script><script>…`, fecharia a tag e executaria código na página. Por isso
 * `<`, `>` e `&` viram escapes Unicode (continuam JSON válido e idêntico ao ler),
 * e os separadores de linha U+2028/U+2029 também.
 */
export function jsonLdSeguro(valor: unknown): string {
  return JSON.stringify(valor)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

export type ItemDeFaq = { question: string; answer: string };

/**
 * Organização + site + perguntas frequentes. Só afirma o que a página MOSTRA:
 *  - o FAQPage usa exatamente as perguntas e respostas visíveis (exigência dos buscadores);
 *  - nada de endereço, avaliação ou preço: o negócio não informou, e inventar
 *    dado estruturado é motivo de penalidade.
 */
export function dadosEstruturados(opcoes: { urlSite: string; telefoneE164: string; faq: ItemDeFaq[] }) {
  const { urlSite, telefoneE164, faq } = opcoes;
  const grafo: Record<string, unknown>[] = [
    {
      '@type': 'Organization',
      '@id': `${urlSite}/#organizacao`,
      name: NOME_DO_SITE,
      url: urlSite,
      contactPoint: {
        '@type': 'ContactPoint',
        telephone: `+${telefoneE164.replace(/\D/g, '')}`,
        contactType: 'customer service',
        availableLanguage: 'pt-BR',
      },
    },
    {
      '@type': 'WebSite',
      '@id': `${urlSite}/#site`,
      url: urlSite,
      name: NOME_DO_SITE,
      inLanguage: 'pt-BR',
      publisher: { '@id': `${urlSite}/#organizacao` },
    },
  ];

  const perguntas = faq.filter((f) => f.question.trim() && f.answer.trim());
  if (perguntas.length > 0) {
    grafo.push({
      '@type': 'FAQPage',
      '@id': `${urlSite}/#faq`,
      mainEntity: perguntas.map((f) => ({
        '@type': 'Question',
        name: f.question,
        acceptedAnswer: { '@type': 'Answer', text: f.answer },
      })),
    });
  }
  return { '@context': 'https://schema.org', '@graph': grafo };
}

/**
 * Descrição da página inicial. Só cita frescor e frete quando o BANCO confirma
 * (mesma regra da faixa de confiança): sem dado, descrição genérica.
 */
export function descricaoDaHome(c: { freshnessMaxDays: number | null; freeShipping: boolean } | null): string {
  const base = 'Ovos caipiras direto da fazenda para a sua casa, por assinatura semanal, quinzenal ou mensal.';
  const partes: string[] = [];
  if (c?.freshnessMaxDays) partes.push(`No máximo ${c.freshnessMaxDays} dias entre a colheita e a entrega.`);
  if (c?.freeShipping) partes.push('Frete incluso na área atendida.');
  return [base, ...partes].join(' ');
}
