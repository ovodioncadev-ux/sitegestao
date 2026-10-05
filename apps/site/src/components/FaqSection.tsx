'use client';

import { WHATSAPP_EXIBICAO } from '@ovo/config/whatsapp';
import { useConteudoSite } from '@/hooks/useConteudoSite';
import { Secao } from './ui';

export function FaqSection() {
  const { conteudo, carregando, erro } = useConteudoSite();

  // O contato vem do código (fonte única do número, D12); o resto do banco.
  const itens = [
    ...(conteudo?.faq ?? []),
    { question: 'Como falo com a Ovo di Onça?', answer: `Pelo WhatsApp: ${WHATSAPP_EXIBICAO}.` },
  ];

  return (
    <Secao id="faq" titulo="Perguntas frequentes">
      {carregando && <p role="status" className="text-center text-suave">Carregando perguntas...</p>}
      {erro && (
        <p role="alert" className="mb-6 text-center text-suave">
          Não foi possível carregar as perguntas agora. Fale com a gente pelo WhatsApp.
        </p>
      )}
      {!carregando && (
        <dl>
          {itens.map((item) => (
            <div key={item.question} className="mb-6">
              <dt className="font-semibold">{item.question}</dt>
              <dd className="mt-1 text-suave">{item.answer}</dd>
            </div>
          ))}
        </dl>
      )}
    </Secao>
  );
}
