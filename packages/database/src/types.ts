/**
 * Tipos do banco.
 *
 * Escritos à mão e mantidos em par com as migrations. São dois papéis:
 * administrador (Fred e Bruna) e cliente. Nem `entregador` nem `producao`
 * existem — ver DECISOES.md. Papel que não se sabe se existe não entra nem
 * no tipo nem no banco.
 *
 * O id é `text` porque o Better Auth gera id em texto, não uuid.
 */

export type PapelUsuario = 'dono' | 'assinante';

export type Perfil = {
  id: string;
  papel: PapelUsuario;
  nome: string;
  telefone: string | null;
  pin_hash: string | null;
  criado_em: string;
  atualizado_em: string;
};

/** O que um usuário comum consegue de fato alterar em `perfis`. */
export type PerfilEditavel = Pick<Perfil, 'nome' | 'telefone'>;
