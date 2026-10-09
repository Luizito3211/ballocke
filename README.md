# HaxBall Local — Real Soccer

Jogo de futebol 2D em Lua puro para LÖVE 11.5. O host é autoritativo para física, árbitro, placar e relógio; os clientes enviam comandos e recebem snapshots. A conexão de jogo usa ENet/UDP. A descoberta de salas usa broadcast UDP e pode ser bloqueada entre laboratórios; nesse caso, entre pelo IPv4 e porta mostrados pelo host.

## Como jogar online

No menu, escolha **Criar sala** no computador host ou **Entrar** nos outros computadores. O host abre a porta UDP 7777; os clientes digitam um endereço anunciado ou usam `IPv4:7777`. O host pode pressionar F2 para alternar 2v2 a 5v5. Todos podem pressionar 1 para vermelho, 2 para azul ou 3 para espectador. Teclas: WASD move, Espaço chuta, setas ajustam o efeito, C centraliza o efeito, +/− ajustam zoom, F3 mostra diagnóstico, F4 mostra colisores, F5 abre calibração local, TAB mostra ping, F11 alterna tela cheia e Esc encerra.

## Testar a rede

No menu, escolha **Teste de conexão**. No computador receptor, pressione R e informe aos outros o IPv4 e a porta 7779 mostrados. No outro computador, pressione C, digite esse IPv4 e pressione Enter. A tela mostra ping e perda estimada. O teste usa UDP e não inicia uma partida.

## Rodar o código

Instale/extraia o LÖVE 11.x e, na raiz do projeto, execute:

```sh
love .
```

Para teste local de duas instâncias, abra dois terminais na raiz:

```sh
love . --host 7777
love . --join 127.0.0.1:7777
```

No Windows, `run.bat` inicia o jogo e `run.bat --test` executa a suíte automatizada. A latência e perda simuladas podem ser ajustadas em `src/config.lua` (`simulatedLatencyMs` e `simulatedPacketLoss`).

## Baixar e jogar

O jogo pronto será publicado na página de Releases do GitHub. **Link da versão mais recente:** [Baixar HaxBall Local](https://github.com/SEU_USUARIO/SEU_REPOSITORIO/releases/latest/download/HaxBallLocal.zip) (substituir pelo link da Release).

1. Baixe e extraia `HaxBallLocal.zip`.
2. Abra `HaxBallLocal.exe` dentro da pasta extraída.
3. Se o Windows SmartScreen avisar, selecione **Mais informações** e depois **Executar assim mesmo**.

## Gerar o build portátil

No Windows, execute `build.bat` na raiz do projeto. O pacote final será gerado em `dist/HaxBallLocal.zip`. Consulte `PUBLISHING.md` para as instruções de publicação.
