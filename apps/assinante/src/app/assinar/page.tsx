import Link from 'next/link';
import { redirect } from 'next/navigation';
import { comoAnonimo, comoUsuario } from '@ovo/database';
import { usuarioAtual } from '@ovo/database/papel';
import { buscarCliente } from '@/lib/assinante';
import { formatarReais, formatarTelefone, WHATSAPP_URL } from '@/lib/formatar';
import { ehFrequencia, lerPlanosPublicos, type PlanoPublico } from '@/lib/planos';
import { FormAcao } from '../_componentes/form-acao';
import { CampoCep } from '../_componentes/campo-cep';
import { CampoMascara } from '../_componentes/campo-mascara';
import { confirmarAssinatura, criarMeuCadastro } from './acoes';

// Depende da sessão: nunca cacheada nem compartilhada entre pessoas.
export const dynamic = 'force-dynamic';

type Busca = { plano?: string };

function ResumoDoPlano({ plano }: { plano: PlanoPublico }) {
  const primeiroMes = Math.round(plano.precoCentavos * (1 - plano.descontoPrimeiroMesPct / 100));
  return (
    <section className="cartao" aria-labelledby="titulo-plano">
      <h2 id="titulo-plano">Plano {plano.nome}</h2>
      <dl className="lista-dados">
        <dt>Valor</dt>
        <dd>
          {formatarReais(plano.precoCentavos)} por mês
          {plano.descontoPrimeiroMesPct > 0 && ` (${formatarReais(primeiroMes)} no 1º mês)`}
        </dd>
        <dt>Entrega</dt>
        <dd>
          A cada {plano.intervaloDias} dias{plano.ancorarEmQuarta && ', sempre às quartas-feiras'}
        </dd>
        <dt>Frete</dt>
        <dd>{plano.freteCentavos === 0 ? 'Incluso' : formatarReais(plano.freteCentavos)}</dd>
        <dt>Frescor</dt>
        <dd>No máximo {plano.freshnessMaxDias} dias entre a coleta e a entrega</dd>
      </dl>
    </section>
  );
}

export default async function Assinar({ searchParams }: { searchParams: Promise<Busca> }) {
  const busca = await searchParams;
  const planos = await comoAnonimo((bd) => lerPlanosPublicos(bd));
  const plano = ehFrequencia(busca.plano) ? planos.find((p) => p.frequencia === busca.plano) : undefined;

  // 1. Sem plano escolhido: vitrine simples.
  if (!plano) {
    return (
      <main className="pagina">
        <h1>Escolha seu plano</h1>
        {planos.length === 0 && <p className="suave">Nenhum plano disponível no momento.</p>}
        {planos.map((p) => (
          <section key={p.frequencia} className="cartao">
            <h2>{p.nome}</h2>
            <p>{formatarReais(p.precoCentavos)} por mês</p>
            <Link className="botao" href={`/assinar?plano=${p.frequencia}`}>
              Escolher {p.nome}
            </Link>
          </section>
        ))}
      </main>
    );
  }

  const destino = `/assinar?plano=${plano.frequencia}`;
  const usuario = await usuarioAtual();

  // 2. Sem conta/sessão: mostra o plano e leva ao cadastro, voltando para cá.
  if (!usuario) {
    return (
      <main className="pagina">
        <h1>Assinar</h1>
        <ResumoDoPlano plano={plano} />
        <section className="cartao">
          <p>Para assinar, crie sua conta. Depois você informa o endereço e confirma o plano.</p>
          <p>
            <Link className="botao" href={`/cadastro?proximo=${encodeURIComponent(destino)}`}>
              Criar conta
            </Link>{' '}
            <Link className="botao botao-secundario" href={`/entrar?proximo=${encodeURIComponent(destino)}`}>
              Já tenho conta
            </Link>
          </p>
        </section>
      </main>
    );
  }

  // 3. Conta de administração não assina.
  if (usuario.papel !== 'assinante') {
    return (
      <main className="pagina">
        <h1>Assinar</h1>
        <p className="msg-info">Esta conta é de administração e não pode assinar um plano.</p>
      </main>
    );
  }

  const dados = await comoUsuario(usuario.usuarioId, async (bd) => {
    const cliente = await buscarCliente(bd, usuario.usuarioId);
    if (!cliente) {
      const perfil = await bd.umaLinha<{ nome: string }>('select nome from perfis where id = $1', [usuario.usuarioId]);
      return { cliente: null, nome: perfil?.nome ?? '', vigente: false, naArea: false };
    }
    const vigente = await bd.umaLinha<{ id: string }>(
      `select id from assinaturas where cliente_id = $1 and status in ('ativa', 'pausada') limit 1`,
      [cliente.id],
    );
    const area = await bd.umaLinha<{ atendido: boolean }>('select cep_dentro_area_entrega($1) as atendido', [
      cliente.cep,
    ]);
    return { cliente, nome: cliente.nome, vigente: Boolean(vigente), naArea: Boolean(area?.atendido) };
  });

  // 4. Já assina: nada a fazer aqui.
  if (dados.vigente) redirect('/');

  // 5. Falta o cadastro (endereço validado).
  if (!dados.cliente) {
    return (
      <main className="pagina">
        <h1>Seu endereço</h1>
        <ResumoDoPlano plano={plano} />
        <section className="cartao">
          <p className="suave">Confira onde vamos entregar. O CEP diz se já atendemos a sua região.</p>
          <FormAcao acao={criarMeuCadastro} rotulo="Continuar">
            <input type="hidden" name="plano" value={plano.frequencia} />

            <label className="campo">
              Nome
              <input name="nome" type="text" defaultValue={dados.nome} required minLength={3} maxLength={120} autoComplete="name" />
            </label>

            <CampoMascara
              nome="telefone"
              rotulo="Telefone (com DDD)"
              tipo="telefone"
              placeholder="(31) 99999-9999"
              autoComplete="tel"
            />

            <CampoCep />

            <label className="campo">
              Rua
              <input name="endereco" type="text" required maxLength={200} autoComplete="address-line1" />
            </label>

            <label className="campo">
              Número
              <input name="numero" type="text" required maxLength={20} />
            </label>

            <label className="campo">
              Complemento (opcional)
              <input name="complemento" type="text" maxLength={100} />
            </label>

            <label className="campo">
              Bairro
              <input name="bairro" type="text" required maxLength={100} />
            </label>

            <label className="campo">
              Cidade
              <input name="cidade" type="text" required maxLength={100} autoComplete="address-level2" />
            </label>

            <label className="campo">
              Estado (sigla)
              <input name="estado" type="text" required maxLength={2} autoComplete="address-level1" />
            </label>
          </FormAcao>
        </section>
      </main>
    );
  }

  const { cliente } = dados;

  // 6. Cadastro feito, mas o CEP está fora da área: sem assinatura.
  if (!dados.naArea) {
    return (
      <main className="pagina">
        <h1>Ainda não entregamos aí</h1>
        <section className="cartao">
          <p>
            O CEP {cliente.cep} ainda não está na nossa área de entrega, então não dá para criar a assinatura agora.
            Seu cadastro ficou guardado.
          </p>
          <p>
            <Link className="botao botao-secundario" href="/dados">
              Corrigir meus dados
            </Link>{' '}
            <a className="botao botao-whatsapp" href={WHATSAPP_URL} target="_blank" rel="noreferrer">
              Falar com a Ovo di Onça
            </a>
          </p>
        </section>
      </main>
    );
  }

  // 7. Confirmação.
  return (
    <main className="pagina">
      <h1>Confirmar assinatura</h1>
      <ResumoDoPlano plano={plano} />

      <section className="cartao" aria-labelledby="titulo-entrega">
        <h2 id="titulo-entrega">Entrega</h2>
        <dl className="lista-dados">
          <dt>Nome</dt>
          <dd>{cliente.nome}</dd>
          <dt>Telefone</dt>
          <dd>{formatarTelefone(cliente.telefone)}</dd>
          <dt>Endereço</dt>
          <dd>
            {cliente.endereco}, {cliente.numero}
            {cliente.complemento && ` — ${cliente.complemento}`}
            <br />
            {cliente.bairro} · {cliente.cidade}/{cliente.estado} · CEP {cliente.cep}
          </dd>
        </dl>
        <p>
          <Link href="/dados">Corrigir meus dados</Link>
        </p>
      </section>

      <section className="cartao">
        <p className="suave">
          Ao confirmar, sua assinatura é criada e a primeira entrega é agendada
          {plano.ancorarEmQuarta && ' para a próxima quarta-feira disponível'}. O pagamento online ainda não está
          disponível: a cobrança é confirmada pela Ovo di Onça (PIX com comprovante enviado pelo WhatsApp).
        </p>
        <FormAcao acao={confirmarAssinatura} rotulo="Confirmar assinatura">
          <input type="hidden" name="plano" value={plano.frequencia} />
        </FormAcao>
      </section>
    </main>
  );
}
