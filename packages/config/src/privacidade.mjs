/**
 * Consentimento de quem pede aviso por estar fora da área de entrega — a ÚNICA
 * fonte do texto e da versão.
 *
 * O banco grava a VERSÃO aceita (`interessados.consentimento_versao`). Mudou o
 * texto de um jeito que muda o que a pessoa autoriza? Some 1 em CONSENTIMENTO_VERSAO:
 * os pedidos antigos continuam ligados ao texto que de fato foi mostrado.
 * O servidor usa esta constante; o navegador nunca diz qual versão aceitou.
 */
export const CONSENTIMENTO_VERSAO = 1;

export const CONSENTIMENTO_TEXTO =
  'Autorizo a Ovo di Onça a usar o contato que informei só para me avisar quando a entrega chegar ao meu CEP. ' +
  'Posso pedir a exclusão dos meus dados a qualquer momento pelo WhatsApp.';
