import { Container, Icone, type NomeIcone } from './ui';

const ITENS: { icone: NomeIcone; texto: string }[] = [
  { icone: 'relogio', texto: 'Máx. 7 dias da colheita à entrega' },
  { icone: 'caminhao', texto: 'Frete incluso na área atendida' },
  { icone: 'calendario', texto: 'Sem fidelidade' },
  { icone: 'selo', texto: '10% de desconto no 1º mês' },
];

export function FaixaConfianca() {
  return (
    <section aria-label="Resumo do serviço" className="border-y border-borda bg-superficie-baixa">
      <Container className="py-6">
        <ul className="m-0 grid list-none grid-cols-1 gap-4 p-0 sm:grid-cols-2 lg:grid-cols-4">
          {ITENS.map((item) => (
            <li key={item.texto} className="flex items-center gap-3 text-[length:var(--texto-pequeno)]">
              <span className="text-ouro-escuro">
                <Icone nome={item.icone} />
              </span>
              {item.texto}
            </li>
          ))}
        </ul>
      </Container>
    </section>
  );
}
