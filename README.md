# dosbox-tv

Container Docker que roda DOSBox Staging + DBGL (DOSBox Game Launcher) com streaming pra TV via
[Sunshine](https://github.com/LizardByte/Sunshine) / Moonlight. Gerenciado pela GUI do OMV8 (Compose plugin)
no host `fenix`.

- Imagem base: `lizardbyte/sunshine:latest-ubuntu-24.04`
- Vídeo: Xorg com driver `dummy` (headless), capturado via VAAPI pelo Sunshine
- Áudio: PulseAudio com sink nulo (`virtual_speaker`), capturado pelo Sunshine
- Launcher de jogos: [DBGL](https://dbgl.org/) 0.99 (build Linux)
- Engine: [dosbox-staging](https://dosbox-staging.github.io/) 0.82.2

## Estrutura

- `Dockerfile` — build da imagem
- `entrypoint.sh` — bootstrap do container (Xorg, fluxbox, pulseaudio, DBGL, Sunshine)
- `xorg-dummy.conf` — config do driver de vídeo dummy
- `compose.yml` — compose gerado pela OMV (referência; a OMV é quem administra de fato)
- `dosbox-tv.env.example` — variáveis de ambiente (arquivo real fica vazio/gerenciado pela OMV)

⚠️ **Os arquivos `Dockerfile`/`entrypoint.sh`/`compose.yml` no host (`/appdata/dosbox-tv/`) são
"auto-gerados pela OMV"** — a GUI do Compose plugin pode sobrescrevê-los quando o app é editado por lá.
Este repositório é a fonte da verdade; sempre que a OMV regenerar os arquivos, recole o conteúdo daqui.
(Já aconteceu de a própria GUI corromper o `Dockerfile` no meio de uma sessão — sempre vale conferir
o conteúdo real em disco depois de mexer na GUI.)

## Volumes

- `/docker/dosbox-tv/home` → `/home/lizard` — home do usuário (config do DOSBox, dados do DBGL)
- `/srv/mergerfs/mediapool/data/games-dos` → `/games` — biblioteca de jogos DOS (persistente)
- `/dev/input` → `/dev/input` — passthrough de teclado/mouse/controle

## Problemas resolvidos (histórico)

### 1. DBGL crashava com `UnsatisfiedLinkError` ao tentar carregar `libswt-win32-*.so`

Causa: o `dbgl096.zip` baixado de dbgl.org é a **distribuição Windows** do DBGL (só tem
`swtwin64.jar`, sem build Linux nenhuma). Corrigido baixando `dbgl099.tar.xz` (build Linux oficial,
com `swtlin64.jar` real) e adicionando `libgtk-3-0t64` + `libwebkit2gtk-4.1-0` como dependências
(SWT no Linux precisa de GTK3/WebKitGTK).

### 2. DOSBox travava com `SDL: Could not initialize video: Couldn't find matching GLX visual`

Causa: o driver `dummy` do Xorg não expõe GLX/3D. O output padrão do dosbox-staging é `opengl`, que
precisa de um contexto GL válido. Corrigido forçando, em `~/.config/dosbox/dosbox-staging.conf`:

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
`/home/lizard/fluxbox.log` e `/home/lizard/dbgl.log` (o `entrypoint.sh` deste repo já reflete isso).

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
copie a pasta do jogo pra `/srv/mergerfs/mediapool/data/games-dos/<NOME_DO_JOGO>` no host. Depois
cadastre no DBGL via **Profile > New Profile**, apontando o **Main executable** pro `.exe` principal
do jogo.
