import type { MetadataRoute } from 'next';

// O domínio público vem do ambiente; sem ele, o robots libera a vitrine e não
// anuncia sitemap. Painel e área logada ficam fora da indexação.
const BASE = process.env.NEXT_PUBLIC_URL_SITE?.replace(/\/$/, '');

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: '*', allow: '/', disallow: ['/conta/', '/gestao/'] }],
    ...(BASE ? { sitemap: `${BASE}/sitemap.xml` } : {}),
  };
}
