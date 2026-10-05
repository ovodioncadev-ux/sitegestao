import { comoUsuario } from '@ovo/database';
import { buscarCliente, exigirSessao } from '@/lib/assinante';
import { formatarTelefone, WHATSAPP_URL } from '@/lib/formatar';
import { Pagina } from '../_componentes/pagina';
import { FormAcao } from '../_componentes/form-acao';
import { CampoMascara } from '../_componentes/campo-mascara';
import { atualizarMeusDados } from '../acoes';

export const dynamic = 'force-dynamic';

export default async function MeusDados() {
  const { usuarioId } = await exigirSessao();
  const cliente = await comoUsuario(usuarioId, (bd) => buscarCliente(bd, usuarioId));

  if (!cliente) {
    return (
      <Pagina titulo="Meus dados">
        <section className="cartao">
          <p>Sua conta ainda não está ligada a um cadastro de assinante.</p>
          <p>
            <a className="botao botao-whatsapp" href={WHATSAPP_URL} target="_blank" rel="noreferrer">
              Falar com a Ovo di Onça no WhatsApp
            </a>
          </p>
        </section>
      </Pagina>
    );
  }

  return (
    <Pagina titulo="Meus dados">
      <section className="cartao">
        <p className="suave">
          Para trocar o e-mail, fale com a gente pelo{' '}
          <a href={WHATSAPP_URL} target="_blank" rel="noreferrer">
            WhatsApp
          </a>
          . E-mail atual: {cliente.email ?? '—'}
        </p>

        <FormAcao acao={atualizarMeusDados} rotulo="Salvar dados">
          <label className="campo">
            Nome
            <input name="nome" type="text" defaultValue={cliente.nome} required minLength={3} maxLength={120} autoComplete="name" />
          </label>

          <CampoMascara
            nome="telefone"
            rotulo="Telefone (com DDD)"
            tipo="telefone"
            valorInicial={formatarTelefone(cliente.telefone)}
            placeholder="(31) 99999-9999"
            autoComplete="tel"
          />

          <CampoMascara
            nome="cep"
            rotulo="CEP"
            tipo="cep"
            valorInicial={cliente.cep ?? ''}
            placeholder="30000-000"
            autoComplete="postal-code"
          />

          <label className="campo">
            Rua
            <input name="endereco" type="text" defaultValue={cliente.endereco ?? ''} required maxLength={200} autoComplete="address-line1" />
          </label>

          <label className="campo">
            Número
            <input name="numero" type="text" defaultValue={cliente.numero ?? ''} required maxLength={20} />
          </label>

          <label className="campo">
            Complemento (opcional)
            <input name="complemento" type="text" defaultValue={cliente.complemento ?? ''} maxLength={100} />
          </label>

          <label className="campo">
            Bairro
            <input name="bairro" type="text" defaultValue={cliente.bairro ?? ''} required maxLength={100} />
          </label>

          <label className="campo">
            Cidade
            <input name="cidade" type="text" defaultValue={cliente.cidade ?? ''} required maxLength={100} autoComplete="address-level2" />
          </label>

          <label className="campo">
            Estado (sigla)
            <input name="estado" type="text" defaultValue={cliente.estado ?? ''} required maxLength={2} autoComplete="address-level1" />
          </label>
        </FormAcao>
      </section>

      <section className="cartao">
        <h2>Seu código de indicação</h2>
        <p>
          <strong>{cliente.codigo_indicacao}</strong>
        </p>
      </section>
    </Pagina>
  );
}
