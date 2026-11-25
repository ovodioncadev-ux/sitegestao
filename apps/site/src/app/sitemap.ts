import type { MetadataRoute } from 'next';

const BASE = process.env.NEXT_PUBLIC_URL_SITE?.replace(/\/$/, '');

// Sem o domínio público configurado não há URL absoluta para publicar: devolve vazio.
export default function sitemap(): MetadataRoute.Sitemap {
  return BASE ? [{ url: `${BASE}/`, changeFrequency: 'monthly', priority: 1 }] : [];
}
