'use client';

import { WHATSAPP_EXIBICAO } from '@ovo/config/whatsapp';

const FAQ_ITEMS = [
  {
    question: 'Como assino?',
    answer: 'Escolha o plano, crie sua conta, informe o endereço (o CEP mostra se já entregamos aí) e confirme a assinatura. Tudo pelo site.',
  },
  {
    question: 'Qual é o prazo de frescor dos ovos?',
    answer: 'No máximo 7 dias entre a colheita na fazenda e a entrega na sua casa, em todos os planos.',
  },
  {
    question: 'O frete é cobrado?',
    answer: 'Não, o frete é grátis para todos os planos dentro da área atendida.',
  },
  {
    question: 'O desconto do 1º mês vale para qualquer forma de pagamento?',
    answer: 'Sim, os 10% de desconto no primeiro mês valem tanto para cartão quanto para PIX.',
  },
  {
    question: 'Como funciona o pagamento?',
    answer: 'Hoje a confirmação é manual: você envia o comprovante do PIX (ou combina o cartão) pelo WhatsApp e a Ovo di Onça confirma o pedido.',
  },
  {
    question: 'Meu bairro é atendido?',
    answer: 'Digite seu CEP na seção Área de entrega. Fora da área atendida ainda não conseguimos entregar.',
  },
  {
    question: 'Como falo com a Ovo di Onça?',
    answer: `Pelo WhatsApp: ${WHATSAPP_EXIBICAO}.`,
  },
];
export function FaqSection() {
  return (
    <section
      id="faq"
      style={{ maxWidth: 'var(--largura-conteudo)', margin: '0 auto', padding: `var(--esp-16) var(--esp-6)` }}
    >
      <h2 style={{ textAlign: 'center', fontSize: 'var(--texto-titulo)' }}>Perguntas frequentes</h2>
      <dl style={{ marginTop: 'var(--esp-8)' }}>
        {FAQ_ITEMS.map((item) => (
          <div key={item.question} style={{ marginBottom: 'var(--esp-6)' }}>
            <dt style={{ fontWeight: 600 }}>{item.question}</dt>
            <dd style={{ color: 'var(--cor-texto-suave)', marginTop: 'var(--esp-1)' }}>{item.answer}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
