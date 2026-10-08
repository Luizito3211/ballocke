# HaxBall Local

Jogo de futebol 2D local para até quatro pessoas no mesmo teclado, feito em Lua com LÖVE 11.5. A partida acontece em um único computador. O projeto não implementa jogo online nem partidas em rede local.

## Como jogar

Abra o jogo e use os controles abaixo. `F2` alterna entre os campos 1v1, 2v2 e 3v3; `R` reinicia a partida e o placar; `Esc` encerra o jogo.

| Ação | Jogador 1 (vermelho) | Jogador 2 (azul) | Jogador 3 (vermelho) | Jogador 4 (azul) |
|---|---|---|---|---|
| Cima | W | Seta para cima | I | Numpad 8 ou 8 |
| Baixo | S | Seta para baixo | K | Numpad 5 ou 5 |
| Esquerda | A | Seta para a esquerda | J | Numpad 4 ou 4 |
| Direita | D | Seta para a direita | L | Numpad 6 ou 6 |
| Chutar | Espaço | Shift direito | U | Numpad 0 ou 0 |

O mouse posiciona o ponto de contato no seletor de efeito no canto inferior direito. Clique em `[C]` ou pressione `C` para centralizá-lo. `F4` alterna o controle de efeito pelo teclado, `F3` mostra/oculta o diagnóstico e `F11` alterna janela e tela cheia.

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

No Windows, execute `build.bat` na raiz do projeto. O script baixa o LÖVE 11.5 portátil oficial de 64 bits para `tools/` se necessário e gera `dist/HaxBallLocal.zip`, sem instalar componentes no sistema. O arquivo inclui o runtime e a licença do LÖVE. Saves futuros devem usar `love.filesystem`; no momento, o jogo não grava saves nem configurações persistentes. Consulte `PUBLISHING.md` quando as instruções de publicação estiverem disponíveis.
