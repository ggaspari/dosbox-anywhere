# dosbox-anywhere — DOSBox Staging + DBGL + Sunshine em um container x86_64
# Imagem agnóstica de distribuição: todo o estado persistente vive em /config,
# a biblioteca de jogos em /games.

FROM lizardbyte/sunshine:latest-ubuntu-24.04

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV DOSBOX_STAGING_VERSION=0.82.2

RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries && \
    apt-get update && \
    apt-get install -y \
    fluxbox \
    xserver-xorg-core \
    xserver-xorg-video-dummy \
    xserver-xorg-input-libinput \
    udev \
    openjdk-17-jre \
    mesa-va-drivers \
    xterm \
    gosu \
    wget \
    unzip \
    xz-utils \
    pulseaudio \
    pulseaudio-utils \
    tzdata \
    libasound2t64 \
    libgl1 \
    libcap2-bin \
    libgtk-3-0t64 \
    libwebkit2gtk-4.1-0 \
    && rm -rf /var/lib/apt/lists/*

RUN setcap cap_sys_admin+ep /usr/bin/sunshine

# dosbox-staging distribui binário Linux apenas para x86_64
RUN wget -O /tmp/dosbox-staging.tar.xz \
    https://github.com/dosbox-staging/dosbox-staging/releases/download/v${DOSBOX_STAGING_VERSION}/dosbox-staging-linux-x86_64-v${DOSBOX_STAGING_VERSION}.tar.xz && \
    mkdir -p /opt/dosbox-staging && \
    tar -xJf /tmp/dosbox-staging.tar.xz -C /opt/dosbox-staging --strip-components=1 && \
    ln -s /opt/dosbox-staging/dosbox /usr/local/bin/dosbox && \
    rm /tmp/dosbox-staging.tar.xz

RUN mkdir -p /opt/dbgl && \
    wget -O /tmp/dbgl.tar.xz https://dbgl.org/download/dbgl099.tar.xz && \
    tar -xJf /tmp/dbgl.tar.xz -C /opt/dbgl && \
    rm /tmp/dbgl.tar.xz

# Todo o estado do container (dados do DBGL, config do dosbox, config do
# Sunshine, logs) fica no home do usuário, que passa a ser /config.
RUN mkdir -p /games /config && \
    usermod -d /config lizard && \
    chown lizard /config

COPY xorg-dummy.conf /etc/X11/xorg-dummy.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /opt/dbgl
ENTRYPOINT ["/entrypoint.sh"]
