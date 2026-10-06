
/** Endereço público do site. Sem a variável, o desenvolvimento local (porta 3002). */
const URL_SITE = process.env.NEXT_PUBLIC_URL_SITE ?? 'http://localhost:3002';

const ETAPAS = ['Plano', 'Conta', 'Endereço', 'Confirmação'] as const;
export type PassoDoFunil = 1 | 2 | 3 | 4;

/**
 * Topo das telas de assinatura (/assinar, /cadastro, /entrar): a mesma marca
 * do site, o caminho de volta e, quando se sabe em que etapa a pessoa está,
 * o indicador de progresso. Sem estado: a etapa vem de quem renderiza.
 */
export function CabecalhoFunil({ passo }: { passo?: PassoDoFunil }) {
  return (
    <header className="funil-topo">
      <div className="funil-topo-linha">
        <a href={URL_SITE} className="funil-marca">
          Ovo di Onça
        </a>
        <a href={URL_SITE} className="funil-voltar">
          Voltar ao site
        </a>
      </div>
      {passo && (
        <ol className="passos" aria-label="Etapas da assinatura">
          {ETAPAS.map((rotulo, i) => {
            const numero = i + 1;
            const estado = numero < passo ? 'feito' : numero === passo ? 'atual' : 'a-fazer';
            return (
              <li key={rotulo} className={`passo passo-${estado}`} aria-current={numero === passo ? 'step' : undefined}>
                <span className="passo-numero" aria-hidden="true">
                  {numero < passo ? '✓' : numero}
                </span>
                <span className="passo-rotulo">
                  {rotulo}
                  {numero < passo && <span className="sr-only"> (concluída)</span>}
                </span>
              </li>
            );
          })}
        </ol>
      )}
    </header>
  );
}

/** Quando o `proximo` é o próprio fluxo de assinatura, o cadastro/entrada é a etapa 2. */
export function passoPeloDestino(proximo: string): PassoDoFunil | undefined {
  return proximo.startsWith('/assinar') ? 2 : undefined;
}

