import type { MetadataRoute } from 'next';
import { urlDoSite } from '@/lib/seo';

export default function sitemap(): MetadataRoute.Sitemap {
  const base = urlDoSite();
  return ['/', '/privacidade', '/termos'].map((caminho) => ({ url: `${base}${caminho}` }));
}
