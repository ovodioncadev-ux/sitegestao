import type { Metadata } from 'next';
import Link from 'next/link';
import { WHATSAPP_EXIBICAO, WHATSAPP_URL } from '@ovo/config/whatsapp';

export const metadata: Metadata = { title: 'Termos de uso', alternates: { canonical: '/termos' } };

// RASCUNHO factual, sujeito a revisão jurídica. Não afirma regras de cobrança ainda não implementadas.
export default function Termos() {
  return (
    <main className="mx-auto max-w-[720px] px-6 py-16 leading-relaxed">
      <h1>Termos de uso</h1>
      <h2 className="mt-8">O serviço</h2>
      <p className="mt-2">A Ovo di Onça vende ovos caipiras por assinatura, com entregas semanais, quinzenais ou mensais na área atendida. Os preços e as condições mostrados nos planos valem no momento da assinatura.</p>
      <h2 className="mt-8">Assinatura</h2>
      <p className="mt-2">Você escolhe o plano, informa o endereço e confirma. Não há fidelidade: você pode pedir o cancelamento a qualquer momento.</p>
      <h2 className="mt-8">Contato</h2>
      <p className="mt-2">Dúvidas e pedidos pelo WhatsApp <a href={WHATSAPP_URL} target="_blank" rel="noreferrer" className="underline">{WHATSAPP_EXIBICAO}</a>.</p>
      <p className="mt-8 text-[length:var(--texto-pequeno)] text-suave">Texto em revisão; será atualizado com os dados completos do responsável.</p>
      <p className="mt-6"><Link href="/" className="underline">Voltar ao início</Link></p>
    </main>
  );
}
