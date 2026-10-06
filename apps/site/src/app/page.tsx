import { SiteApp } from '@/components/SiteApp';
import { buscarDadosDoSite } from '@/lib/dados';
import { WHATSAPP_E164 } from '@ovo/config/whatsapp';
import { dadosEstruturados, descricaoDaHome, jsonLdSeguro, urlDoSite } from '@/lib/seo';

// Planos, FAQ e bairros vêm do banco: a página é montada a cada pedido (os dados têm cache de 30 s),
// para que o HTML que o buscador recebe já traga o conteúdo e nunca fique congelado do build.
export const dynamic = 'force-dynamic';

export async function generateMetadata() {
  const { conteudo } = await buscarDadosDoSite();
  return { description: descricaoDaHome(conteudo) };
}

export default async function Pagina() {
  const dados = await buscarDadosDoSite();
  const estruturados = dadosEstruturados({
    urlSite: urlDoSite(),
    telefoneE164: WHATSAPP_E164,
    faq: dados.conteudo?.faq ?? [],
  });
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdSeguro(estruturados) }} />
      <SiteApp dados={dados} />
    </>
  );
}
