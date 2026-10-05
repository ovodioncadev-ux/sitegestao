import { CHAVES_STATUS_CLIENTE, STATUS_CLIENTE } from '@/lib/rotulos';

export type PlanoOpcao = { frequencia: string; nome: string };

export type ValoresCliente = {
  nome?: string;
  email?: string | null;
  telefone?: string | null;
  cep?: string | null;
  endereco?: string | null;
  numero?: string | null;
  complemento?: string | null;
  bairro?: string | null;
  cidade?: string | null;
  estado?: string | null;
  status?: string;
  frequencia?: string | null;
  pentes_padrao?: number | null;
  duzias_padrao?: number | null;
  desconto_primeiro_mes_aplicavel?: boolean;
};

/** Os campos do formulário de cliente, iguais no cadastro e na edição. */
export function CamposCliente({
  planos,
  valores = {},
  planoTravado = false,
}: {
  planos: PlanoOpcao[];
  valores?: ValoresCliente;
  /** Cliente com assinatura vigente: o plano se altera na assinatura, não aqui. */
  planoTravado?: boolean;
}) {
  return (
    <>
      <div className="grade">
        <div>
          <label htmlFor="nome">Nome *</label>
          <input id="nome" name="nome" required maxLength={120} defaultValue={valores.nome ?? ''} />
        </div>
        <div>
          <label htmlFor="email">E-mail</label>
          <input id="email" name="email" type="email" maxLength={254} defaultValue={valores.email ?? ''} />
        </div>
        <div>
          <label htmlFor="telefone">Telefone (com DDD)</label>
          <input
            id="telefone"
            name="telefone"
            placeholder="(31) 99999-9999"
            defaultValue={valores.telefone ?? ''}
          />
        </div>
      </div>

      <div className="grade">
        <div>
          <label htmlFor="cep">CEP</label>
          <input id="cep" name="cep" placeholder="30110-000" defaultValue={valores.cep ?? ''} />
        </div>
        <div>
          <label htmlFor="endereco">Endereço (rua)</label>
          <input id="endereco" name="endereco" maxLength={200} defaultValue={valores.endereco ?? ''} />
        </div>
        <div>
          <label htmlFor="numero">Número</label>
          <input id="numero" name="numero" maxLength={20} defaultValue={valores.numero ?? ''} />
        </div>
        <div>
          <label htmlFor="complemento">Complemento</label>
          <input id="complemento" name="complemento" maxLength={100} defaultValue={valores.complemento ?? ''} />
        </div>
        <div>
          <label htmlFor="bairro">Bairro</label>
          <input id="bairro" name="bairro" maxLength={100} defaultValue={valores.bairro ?? ''} />
        </div>
        <div>
          <label htmlFor="cidade">Cidade</label>
          <input id="cidade" name="cidade" maxLength={100} defaultValue={valores.cidade ?? ''} />
        </div>
        <div>
          <label htmlFor="estado">Estado (sigla)</label>
          <input id="estado" name="estado" maxLength={2} placeholder="MG" defaultValue={valores.estado ?? ''} />
        </div>
      </div>

      <div className="grade">
        <div>
          <label htmlFor="status">Status</label>
          <select id="status" name="status" defaultValue={valores.status ?? 'cadastro_andamento'}>
            {CHAVES_STATUS_CLIENTE.map((chave) => (
              <option key={chave} value={chave}>
                {STATUS_CLIENTE[chave]}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="frequencia">Plano</label>
          <select
            id="frequencia"
            name="frequencia"
            defaultValue={valores.frequencia ?? ''}
            disabled={planoTravado}
          >
            <option value="">— sem plano —</option>
            {planos.map((p) => (
              <option key={p.frequencia} value={p.frequencia}>
                {p.nome}
              </option>
            ))}
          </select>
          {planoTravado && (
            <>
              <input type="hidden" name="frequencia" value={valores.frequencia ?? ''} />
              <span className="suave">Com assinatura vigente, o plano é trocado na assinatura.</span>
            </>
          )}
        </div>
        <div>
          <label htmlFor="pentes_padrao">Pentes por entrega</label>
          <input
            id="pentes_padrao"
            name="pentes_padrao"
            inputMode="numeric"
            placeholder="1"
            defaultValue={valores.pentes_padrao ?? ''}
          />
        </div>
        <div>
          <label htmlFor="duzias_padrao">Dúzias por entrega</label>
          <input
            id="duzias_padrao"
            name="duzias_padrao"
            inputMode="numeric"
            placeholder="0"
            defaultValue={valores.duzias_padrao ?? ''}
          />
        </div>
      </div>

      <label>
        <input
          type="checkbox"
          name="sem_desconto"
          defaultChecked={valores.desconto_primeiro_mes_aplicavel === false}
        />{' '}
        Sem desconto no primeiro mês
      </label>
    </>
  );
}
