import type { Metadata } from 'next';
import Link from 'next/link';
import { WHATSAPP_EXIBICAO, WHATSAPP_URL } from '@ovo/config/whatsapp';

export const metadata: Metadata = { title: 'Política de privacidade', alternates: { canonical: '/privacidade' } };

// RASCUNHO factual: descreve só o que o sistema de fato faz. Precisa de revisão jurídica e de
// identificação do controlador (razão social/CNPJ) antes de valer como documento final.
export default function Privacidade() {
  return (
    <main className="mx-auto max-w-[720px] px-6 py-16 leading-relaxed">
      <h1>Política de privacidade</h1>
      <p className="mt-2 text-suave">Como a Ovo di Onça trata os seus dados, em linguagem simples.</p>

      <h2 className="mt-8">O que coletamos e por quê</h2>
      <ul className="mt-2 list-disc pl-6">
        <li><strong>Ao assinar:</strong> nome, e-mail, telefone e endereço de entrega, para criar a conta, entregar os ovos e cobrar a assinatura.</li>
        <li><strong>No “Avise-me” (CEP fora da área):</strong> CEP e, se você quiser, nome, telefone ou e-mail, só para avisar quando a entrega chegar ao seu CEP. Só guardamos com o seu consentimento.</li>
        <li><strong>Contagem de visitas ao funil:</strong> registramos etapas anônimas (por exemplo, “clicou em um plano”), sem nome, e-mail ou outro dado pessoal.</li>
        <li><strong>Endereço de rede (IP):</strong> usado por pouco tempo apenas para limitar tentativas abusivas (por exemplo, de login).</li>
      </ul>

      <h2 className="mt-8">Cookies</h2>
      <p className="mt-2">Usamos apenas o cookie de sessão necessário para você entrar na sua conta. Não usamos cookies de publicidade nem de análise de terceiros.</p>

      <h2 className="mt-8">Com quem compartilhamos</h2>
      <p className="mt-2">Não vendemos dados. Quando o pagamento online estiver disponível, o provedor de pagamento recebe o necessário para processar a cobrança.</p>

      <h2 className="mt-8">Seus direitos</h2>
      <p className="mt-2">
        Você pode pedir acesso, correção ou exclusão dos seus dados a qualquer momento pelo WhatsApp{' '}
        <a href={WHATSAPP_URL} target="_blank" rel="noreferrer" className="underline">{WHATSAPP_EXIBICAO}</a>.
      </p>

      <p className="mt-8 text-[length:var(--texto-pequeno)] text-suave">
        Este texto está em revisão e será atualizado com a identificação completa do responsável pelo tratamento.
      </p>
      <p className="mt-6"><Link href="/" className="underline">Voltar ao início</Link></p>
    </main>
  );
}
