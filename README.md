# HaxBall Local

Jogo de futebol 2D local para até quatro pessoas no mesmo teclado, feito em Lua com LÖVE 11.5. A partida acontece em um único computador. O projeto não implementa jogo online nem partidas em rede local.

## Como jogar

Abra o jogo e use os controles abaixo. `F2` percorre os modos 1v1, 2v2, 3v3, 4v4 e 5v5 sem mudar a quadra; nesta versão, o teclado controla no máximo quatro jogadores locais. `R` reinicia a partida e o placar; `Esc` encerra o jogo.

| Ação | Jogador 1 (vermelho) | Jogador 2 (azul) | Jogador 3 (vermelho) | Jogador 4 (azul) |
|---|---|---|---|---|
| Cima | W | Seta para cima | I | Numpad 8 ou 8 |
| Baixo | S | Seta para baixo | K | Numpad 5 ou 5 |
| Esquerda | A | Seta para a esquerda | J | Numpad 4 ou 4 |
| Direita | D | Seta para a direita | L | Numpad 6 ou 6 |
| Chutar | Espaço | Shift direito | U | Numpad 0 ou 0 |

O campo RS mede 3000 × 1500 unidades, com paredes externas de contenção 150 unidades além das linhas. O mundo usa (0, 0) no centro da quadra. A janela mostra provisoriamente a arena inteira; a câmera RS será implementada na Fase 2. `F4` mostra/oculta os colisores reais (paredes externas em vermelho, traves em amarelo e redes em ciano); `F3` mostra/oculta o diagnóstico e `F11` alterna janela e tela cheia.

O mouse posiciona o ponto de contato no seletor de efeito no canto inferior direito. Clique em `[C]` ou pressione `C` para centralizá-lo.

## Rodar o código

Instale o LÖVE 11.x e, na raiz do projeto, execute:

```sh
love .
```

No Windows, também é possível iniciar com `run.bat`. Para executar os testes de física pelo script, use `run.bat --test`.

## Baixar e jogar

O jogo pronto será publicado na página de Releases do GitHub. **Link da versão mais recente:** [Baixar HaxBall Local](https://github.com/SEU_USUARIO/SEU_REPOSITORIO/releases/latest/download/HaxBallLocal.zip) (substituir pelo link da Release).

1. Baixe e extraia `HaxBallLocal.zip`.
2. Abra `HaxBallLocal.exe` dentro da pasta extraída.
3. Se o Windows SmartScreen avisar, selecione **Mais informações** e depois **Executar assim mesmo**.

## Gerar o build portátil

No Windows, execute `build.bat` na raiz do projeto. O pacote final será gerado em `dist/HaxBallLocal.zip`. Consulte as instruções de publicação em `PUBLISHING.md` quando estiverem disponíveis.
