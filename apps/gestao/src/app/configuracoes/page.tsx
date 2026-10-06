import { comoUsuario } from '@ovo/database';
import { exigirDono } from '@ovo/database/papel';
import { FormAcao } from '../_componentes/form-acao';
import { Pagina, SemPermissao } from '../_componentes/pagina';
import { centavosParaCampo, formatarReais } from '@/lib/formatar';
import { salvarConfiguracao, salvarPlano } from './acoes';

export const dynamic = 'force-dynamic';

type Config = {
  preco_pente_centavos: number;
  preco_duzia_centavos: number;
  dia_corte: number;
  hora_corte: string;
  bonus_indicador_pct: string;
  teto_credito_indicacao_pct: string;
  exigir_pagamento_antes_da_1a_entrega: boolean;
  dias_para_pagar_1a_fatura: number;
};

type Plano = {
  id: number;
  frequencia: string;
  nome: string;
  intervalo_dias: number;
  entregas_por_mes: number;
  freshness_max_dias: number;
  frete_centavos: number;
  desconto_primeiro_mes_pct: string;
  ancorar_em_quarta: boolean;
  ativo: boolean;
  selo: string | null;
};

const DIAS = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];

export default async function Configuracoes() {
  const autorizacao = await exigirDono();
  if (!autorizacao.ok) return <SemPermissao mensagem={autorizacao.erro} />;

  const { config, planos } = await comoUsuario(autorizacao.usuario.usuarioId, async (bd) => ({
    config: await bd.umaLinha<Config>(
      `select preco_pente_centavos, preco_duzia_centavos, dia_corte, to_char(hora_corte, 'HH24:MI') as hora_corte,
              bonus_indicador_pct, teto_credito_indicacao_pct,
              exigir_pagamento_antes_da_1a_entrega, dias_para_pagar_1a_fatura
         from config_negocio where id = 1`,
    ),
    planos: await bd.consultar<Plano>(
      `select id, frequencia::text, nome, intervalo_dias, entregas_por_mes, freshness_max_dias, frete_centavos,
              desconto_primeiro_mes_pct, ancorar_em_quarta, ativo, selo
         from planos order by intervalo_dias`,
    ),
  }));

  if (!config) {
    return (
      <Pagina titulo="Configurações">
        <p className="msg-erro">A linha de configuração não existe no banco. Rode as migrations.</p>
      </Pagina>
    );
  }

  return (
    <Pagina titulo="Configurações">
      <h2>Preços e corte</h2>
      <FormAcao acao={salvarConfiguracao} rotulo="Salvar configuração">
        <div className="grade">
          <div>
            <label htmlFor="preco_pente">Preço da entrega de 1 pente (30 ovos), R$</label>
            <input id="preco_pente" name="preco_pente" inputMode="decimal" required
              defaultValue={centavosParaCampo(config.preco_pente_centavos)} />
          </div>
          <div>
            <label htmlFor="preco_duzia">Preço da dúzia avulsa, R$</label>
            <input id="preco_duzia" name="preco_duzia" inputMode="decimal" required
              defaultValue={centavosParaCampo(config.preco_duzia_centavos)} />
          </div>
          <div>
            <label htmlFor="dia_corte">Dia do corte</label>
            <select id="dia_corte" name="dia_corte" defaultValue={config.dia_corte}>
              {DIAS.map((d, i) => (
                <option key={d} value={i}>
                  {d}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="hora_corte">Hora do corte</label>
            <input id="hora_corte" name="hora_corte" type="time" required defaultValue={config.hora_corte} />
          </div>
          <div>
            <label htmlFor="bonus">Bônus do indicador (%) — na fatura do mês em que o indicado paga a 1ª</label>
            <input id="bonus" name="bonus_indicador_pct" inputMode="decimal" required
              defaultValue={Number(config.bonus_indicador_pct)} />
          </div>
          <div>
            <label htmlFor="teto">Teto de crédito por indicação (%)</label>
            <input id="teto" name="teto_credito_indicacao_pct" inputMode="decimal" required
              defaultValue={Number(config.teto_credito_indicacao_pct)} />
          </div>
          <div>
            <label htmlFor="exigir_pagamento">
              <input id="exigir_pagamento" name="exigir_pagamento" type="checkbox"
                defaultChecked={config.exigir_pagamento_antes_da_1a_entrega} />{' '}
              Só entregar depois do 1º pagamento (D8)
            </label>
            <p className="suave">
              Desligado: a assinatura nasce com a 1ª entrega agendada, como sempre. Ligado: nasce aguardando o
              pagamento da 1ª fatura (com o desconto do 1º mês) e a entrega só é agendada quando o pagamento for
              confirmado. Vale só para assinaturas novas.
            </p>
          </div>
          <div>
            <label htmlFor="dias_pagar">Dias para pagar a 1ª fatura</label>
            <input id="dias_pagar" name="dias_para_pagar_1a_fatura" inputMode="numeric" required
              defaultValue={config.dias_para_pagar_1a_fatura} />
            <p className="suave">Passado o prazo sem pagamento, a assinatura é cancelada pela rotina diária.</p>
          </div>
        </div>
      </FormAcao>
      <p className="suave">
        Valor mensal de cada plano = preço do pente × entregas por mês (com 10% na 1ª fatura, se o plano tiver desconto).
        Faturas já criadas não mudam.
      </p>

      <h2>Planos</h2>
      {planos.length === 0 && <p>Nenhum plano cadastrado.</p>}
      {planos.map((p) => (
        <details key={p.id} open>
          <summary>
            {p.nome} — {formatarReais(config.preco_pente_centavos * p.entregas_por_mes)}/mês
            {p.ativo ? '' : ' (inativo)'}
          </summary>
          <FormAcao acao={salvarPlano} rotulo={`Salvar ${p.nome}`}>
            <input type="hidden" name="id" value={p.id} />
            <div className="grade">
              <div>
                <label htmlFor={`nome-${p.id}`}>Nome</label>
                <input id={`nome-${p.id}`} name="nome" required maxLength={60} defaultValue={p.nome} />
              </div>
              <div>
                <label htmlFor={`int-${p.id}`}>Intervalo entre entregas (dias)</label>
                <input id={`int-${p.id}`} name="intervalo_dias" inputMode="numeric" required defaultValue={p.intervalo_dias} />
              </div>
              <div>
                <label htmlFor={`epm-${p.id}`}>Entregas cobradas por mês</label>
                <input id={`epm-${p.id}`} name="entregas_por_mes" inputMode="numeric" required defaultValue={p.entregas_por_mes} />
              </div>
              <div>
                <label htmlFor={`fr-${p.id}`}>Frescor máximo (dias)</label>
                <input id={`fr-${p.id}`} name="freshness_max_dias" inputMode="numeric" required defaultValue={p.freshness_max_dias} />
              </div>
              <div>
                <label htmlFor={`fre-${p.id}`}>Frete, R$</label>
                <input id={`fre-${p.id}`} name="frete" inputMode="decimal" required defaultValue={centavosParaCampo(p.frete_centavos)} />
              </div>
              <div>
                <label htmlFor={`desc-${p.id}`}>Desconto do 1º mês (%)</label>
                <input id={`desc-${p.id}`} name="desconto_primeiro_mes_pct" inputMode="decimal" required
                  defaultValue={Number(p.desconto_primeiro_mes_pct)} />
              </div>
              <div>
                <label htmlFor={`selo-${p.id}`}>Selo no site (deixe vazio para nenhum)</label>
                <input id={`selo-${p.id}`} name="selo" maxLength={30} defaultValue={p.selo ?? ''} placeholder="Ex.: Recomendado" />
              </div>
              <div>
                <label>
                  <input type="checkbox" name="ancorar_em_quarta" defaultChecked={p.ancorar_em_quarta} /> Entregar sempre na quarta-feira
                </label>
              </div>
              <div>
                <label>
                  <input type="checkbox" name="ativo" defaultChecked={p.ativo} /> Plano ativo (aparece no site)
                </label>
              </div>
            </div>
          </FormAcao>
        </details>
      ))}
    </Pagina>
  );
}
