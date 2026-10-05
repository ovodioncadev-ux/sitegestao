/**
 * Resultado de uma Server Action que o formulário sabe mostrar.
 * Fica num arquivo próprio, sem nenhum import de servidor, porque o
 * componente de formulário (que roda no navegador) também usa este tipo.
 */
export type Estado = { ok: boolean; mensagem: string } | null;

/** Assinatura que toda ação de formulário tem (contrato do useActionState). */
export type AcaoDeFormulario = (estado: Estado, dados: FormData) => Promise<Estado>;
