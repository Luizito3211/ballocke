# Publicação no GitHub

## 1. Criar o repositório

1. No GitHub, crie um repositório vazio para o projeto.
2. Não marque as opções para criar README, `.gitignore` ou licença: esses arquivos e o commit inicial já existem localmente.
3. Copie a URL HTTPS ou SSH do repositório. Nos comandos abaixo, substitua `OWNER/REPO` pela conta ou organização e pelo nome escolhidos.

## 2. Conectar e enviar o branch `main`

Na pasta local do projeto, conecte o repositório remoto e envie o branch:

```sh
git remote add origin https://github.com/OWNER/REPO.git
git push -u origin main
```

Se `origin` já estiver configurado, confira a URL e não adicione o remoto novamente.

## 3. Preparar o arquivo da Release

No Windows, gere o pacote portátil na raiz do projeto:

```bat
build.bat
```

Confirme que `dist/HaxBallLocal.zip` foi criado e contém o executável, as DLLs do LÖVE e `license.txt`.

## 4. Criar a Release `v1.0.0`

1. No GitHub, abra **Releases** e escolha **Draft a new release**.
2. Crie a tag `v1.0.0`, apontando para o branch `main`.
3. Use `HaxBall Local v1.0.0` como título.
4. Anexe `dist/HaxBallLocal.zip` aos arquivos binários da Release.
5. Publique a Release.

## 5. Link direto para a versão mais recente

O link estável para baixar o arquivo anexado será:

```text
https://github.com/OWNER/REPO/releases/latest/download/HaxBallLocal.zip
```

Substitua `OWNER/REPO` pelos valores do repositório. O nome do arquivo precisa continuar exatamente `HaxBallLocal.zip` para esse link funcionar.
