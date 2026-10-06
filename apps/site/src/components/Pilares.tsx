import { Cartao, Icone, Secao, type NomeIcone } from './ui';

// Só promessas que o negócio confirma (DECISOES.md): nada de metragem, selo ou prazo inventado.
const PILARES: { icone: NomeIcone; titulo: string; texto: string }[] = [
  {
    icone: 'folha',
    titulo: 'Criação livre',
    texto: 'Galinhas criadas soltas, ao ar aberto, e ovos que chegam à sua casa direto da fazenda.',
  },
  {
    icone: 'caminhao',
    titulo: 'Entrega em dia fixo',
    texto: 'Entregamos às quartas-feiras, na frequência do seu plano, sem você precisar buscar nada.',
  },
  {
    icone: 'calendario',
    titulo: 'Sem amarras',
    texto: 'Sem fidelidade. Pause ou cancele quando precisar, pela área do assinante ou pelo WhatsApp.',
  },
];

export function Pilares() {
  return (
    <Secao
      titulo="Por que receber direto do produtor"
      subtitulo="Sem intermediário e sem prateleira: o ovo sai da fazenda e vem para você."
    >
      <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
        {PILARES.map((p) => (
          <Cartao key={p.titulo}>
            <span className="text-secundaria">
              <Icone nome={p.icone} className="h-8 w-8" />
            </span>
            <h3 className="mt-3 font-semibold">{p.titulo}</h3>
            <p className="mt-2 text-suave">{p.texto}</p>
          </Cartao>
        ))}
      </div>
    </Secao>
  );
}
