import { Secao } from './ui';

const PASSOS = [
  { titulo: 'Escolha o plano', texto: 'Semanal, quinzenal ou mensal, conforme o consumo da sua casa.' },
  { titulo: 'Crie sua conta', texto: 'Só nome, e-mail e senha. Depois, o endereço de entrega.' },
  { titulo: 'Confirme o CEP', texto: 'Mostramos na hora se já entregamos no seu endereço.' },
  { titulo: 'Receba em dia fixo', texto: 'Acompanhe entregas e faturas na sua área do assinante.' },
];

export function ComoFunciona() {
  return (
    <Secao id="como-funciona" titulo="Como funciona" fundo="baixo">
      <ol className="m-0 grid list-none grid-cols-1 gap-6 p-0 sm:grid-cols-2 lg:grid-cols-4">
        {PASSOS.map((passo, i) => (
          <li key={passo.titulo}>
            <span className="flex h-10 w-10 items-center justify-center rounded-pilula bg-ouro font-semibold text-sobre-ouro">
              {i + 1}
            </span>
            <h3 className="mt-3 font-semibold">{passo.titulo}</h3>
            <p className="mt-1 text-suave">{passo.texto}</p>
          </li>
        ))}
      </ol>
    </Secao>
  );
}
