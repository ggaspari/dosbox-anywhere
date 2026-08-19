# dosbox-anywhere

Container Docker que roda DOSBox Staging + DBGL (DOSBox Game Launcher) com streaming pra TV via
[Sunshine](https://github.com/LizardByte/Sunshine) / Moonlight.

Fork **agnóstico de distribuição** do [dosbox-tv](https://github.com/ggaspari/dosbox-tv): roda em
qualquer host Linux x86_64 com Docker (ou Podman com compose), sem depender de OMV, caminhos
específicos de host ou GIDs fixos. Todo o estado do
container vive em dois volumes:

- **`/config`** — home do usuário do container: dados do DBGL, config do DOSBox, config/pareamentos
  do Sunshine, logs. Default no host: `./dockerdata/dosbox-anywhere`
- **`/games`** — biblioteca de jogos DOS. Default no host: `./games`

Componentes:

- Imagem base: `lizardbyte/sunshine:latest-ubuntu-24.04`
- Vídeo: Xorg com driver `dummy` (headless), capturado via VAAPI pelo Sunshine
- Áudio: PulseAudio com sink nulo (`virtual_speaker`), capturado pelo Sunshine
- Launcher de jogos: [DBGL](https://dbgl.org/) 0.99 (build Linux)
- Engine: [dosbox-staging](https://dosbox-staging.github.io/) 0.82.2

## Requisitos

- Host Linux **x86_64** (o binário do dosbox-staging só é distribuído pra essa arquitetura; a
  imagem é pinada com `platform: linux/amd64`)
- GPU com `/dev/dri` (VAAPI) pro encode do Sunshine
- `/dev/uinput` e `/dev/input` acessíveis (input virtual do Moonlight + passthrough de
  teclado/mouse/controle)

## Uso

A imagem pronta é **pública** em [`ghcr.io/ggaspari/dosbox-anywhere`](https://github.com/users/ggaspari/packages/container/package/dosbox-anywhere)
(buildada pelo GitHub Actions a cada push na `main`; tags `vX.Y.Z` geram versões `X.Y.Z`/`X.Y`).
Não precisa de login no registry nem de clonar o repositório — só do `compose.yml`:

```sh
mkdir dosbox-anywhere && cd dosbox-anywhere
wget https://raw.githubusercontent.com/ggaspari/dosbox-anywhere/main/compose.yml
docker compose up -d
```

Pra buildar localmente em vez de puxar a imagem publicada (desenvolvimento):

```sh
git clone https://github.com/ggaspari/dosbox-anywhere && cd dosbox-anywhere
docker compose -f compose.yml -f compose.build.yml up -d --build
```

Na primeira subida o Sunshine gera config nova em `dockerdata/dosbox-anywhere/` — acesse a
web UI dele (`https://<host>:47990`) pra criar usuário e parear o Moonlight.

Pra customizar, copie `.env.example` pra `.env`:

| Variável | Default | Descrição |
|---|---|---|
| `PUID` / `PGID` | `1000` / `1000` | Dono dos arquivos em `/config` e `/games` |
| `TZ` | `UTC` | Timezone (formato IANA, ex: `America/Bahia`) |
| `RENDER_GID` | *auto* | GID do grupo dono de `/dev/dri/renderD128`; auto-detectado dentro do container, só defina se a detecção falhar |
| `CONFIG_DIR` | `./dockerdata/dosbox-anywhere` | Caminho no host do volume `/config` |
| `GAMES_DIR` | `./games` | Caminho no host do volume `/games` |

O `network_mode: host` é intencional: o Sunshine precisa de várias portas TCP/UDP e o mDNS pro
discovery do Moonlight funcionar sem configuração manual.

## Migrando de uma instalação antiga (volume em `/home/lizard`)

Versões anteriores montavam o home em `/home/lizard`. Agora o home do usuário do container **é**
`/config`. Pra migrar, basta copiar o conteúdo do volume antigo pro novo:

```sh
cp -a /docker/dosbox-tv/home/. ./dockerdata/dosbox-anywhere/
```

Nada muda dentro dos arquivos — DBGL (`-Ddbgl.data.userhome=true`), dosbox e Sunshine resolvem
tudo relativo ao `$HOME`, que agora aponta pra `/config`.

## Estrutura

- `Dockerfile` — build da imagem
- `entrypoint.sh` — bootstrap do container (Xorg, fluxbox, pulseaudio, DBGL, Sunshine)
- `xorg-dummy.conf` — config do driver de vídeo dummy
- `compose.yml` — orquestração (docker compose), usando a imagem publicada no GHCR
- `compose.build.yml` — override pra buildar a imagem localmente
- `.github/workflows/build.yml` — CI que builda e publica a imagem no GHCR
- `.env.example` — variáveis de ambiente disponíveis

## Problemas resolvidos (histórico)

### 1. DBGL crashava com `UnsatisfiedLinkError` ao tentar carregar `libswt-win32-*.so`

Causa: o `dbgl096.zip` baixado de dbgl.org é a **distribuição Windows** do DBGL (só tem
`swtwin64.jar`, sem build Linux nenhuma). Corrigido baixando `dbgl099.tar.xz` (build Linux oficial,
com `swtlin64.jar` real) e adicionando `libgtk-3-0t64` + `libwebkit2gtk-4.1-0` como dependências
(SWT no Linux precisa de GTK3/WebKitGTK).

### 2. DOSBox travava com `SDL: Could not initialize video: Couldn't find matching GLX visual`

Causa: o driver `dummy` do Xorg não expõe GLX/3D. O output padrão do dosbox-staging é `opengl`, que
precisa de um contexto GL válido. Corrigido forçando, em `/config/.config/dosbox/dosbox-staging.conf`:

```ini
[sdl]
output           = texture
texture_renderer = software
```

Isso faz o SDL renderizar via software puro, sem precisar de GLX/aceleração 3D nenhuma.

### 3. Fluxbox e DBGL sem supervisão — se caíssem, ficavam mortos até reinício manual

O DBGL tem um bug próprio que derruba o processo Java inteiro em certas telas (ver item 5), e o
fluxbox pode cair silenciosamente sem log nenhum. Nenhum dos dois tinha *restart* automático.
Corrigido envolvendo os dois em loops de supervisão no `entrypoint.sh`, com saída persistida em
`/config/fluxbox.log` e `/config/dbgl.log`.

### 4. Log dos processos supervisionados vazio / permission denied

Os arquivos de log eram criados como `root` (dentro do `entrypoint.sh`, antes do `gosu lizard`), mas
fluxbox/DBGL rodam como `lizard` — dava `Permission denied` silencioso na hora de escrever,
travando o loop de supervisão inteiro antes mesmo de rodar o processo real. Corrigido com um
`chown "$PUID":"$PGID"` logo após criar cada arquivo de log.

### 5. Wizard "Add Game" do DBGL crashava com `IllegalArgumentException: Argument cannot be null`

Duas causas combinadas, ambas em `AddGameWizardDialog.updateControlsByProfile()`:

- As tabelas de referência do banco (Developers/Publishers/Genres/PublYears/Status) estavam
  completamente vazias (o instalador do DBGL 0.99 não as semeia por padrão) — mitigado inserindo
  uma linha em branco em cada uma (mesmo padrão que o DBGL já usa pros campos "Custom").
- **Causa real do crash**: a wizard lê a chave clássica `cycles` da seção `[cpu]` do config de forma
  direta, mas o dosbox-staging usa `cpu_cycles`/`cpu_cycles_protected`. Corrigido adicionando a chave
  `cycles = 3000` de volta no config da versão do DOSBox cadastrada no DBGL (dosbox-staging ignora
  chaves que não reconhece, então não afeta a emulação).

Também corrigido, por completude/consistência: o registro da versão do DOSBox no DBGL estava
cadastrado como `Family: Official` / `Version: 0.74-3` (DOSBox clássico), quando na verdade é
dosbox-staging. Atualizado para `Family: DOSBox Staging` / `Version: 0.82.0` — isso ativa a lógica
de "geração" do DBGL pra várias outras telas (output, scaler, etc.) que dependem corretamente
do fork/versão detectados.

### 6. Sem áudio em jogos, mesmo com DOSBox/Sound Blaster configurados certo

Efeito colateral de um restart manual do processo DBGL feito durante debug, que esqueceu de
exportar `XDG_RUNTIME_DIR` — sem essa variável o PulseAudio não é encontrado pelo SDL, que cai
pro ALSA (inexistente no container) e desativa o som silenciosamente
(`MIXER: Sound output disabled ('nosound' mode)`). O `entrypoint.sh` real já define essa variável
antes de subir o DBGL; resolvido recriando o container do zero.

## Adicionando jogos

Jogos GOG.com (DOS/Sierra etc.) geralmente vêm como instalador InnoSetup — extraia com
[innoextract](https://constexpr.org/innoextract/) (sem precisar rodar o instalador interativo) e
copie a pasta do jogo pro diretório de games no host (`games/<NOME_DO_JOGO>` por default). Depois
cadastre no DBGL via **Profile > New Profile**, apontando o **Main executable** pro `.exe` principal
do jogo.
