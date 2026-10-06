import type { MetadataRoute } from 'next';

// Área de conta/painel: nada aqui deve ser indexado (a vitrine pública é o app do site).
export default function robots(): MetadataRoute.Robots {
  return { rules: { userAgent: '*', disallow: '/' } };
}
