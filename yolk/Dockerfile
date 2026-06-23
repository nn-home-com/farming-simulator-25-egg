# Yolk image for the Farming Simulator 25 dedicated server (Wine, headless).
#
# Designed for Pterodactyl / Calagopus: the container runs as the unprivileged
# "container" user with its home at /home/container, and the egg's parsed startup
# command is provided through the $STARTUP environment variable which entrypoint.sh
# evaluates. All persistent data (Wine prefix, game files, savegames) lives under
# /home/container so it survives container re-creation.
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="farming-simulator-25-server"
LABEL org.opencontainers.image.description="Headless FS25 dedicated server under Wine for Pterodactyl/Calagopus"

ENV DEBIAN_FRONTEND=noninteractive

# Enable 32-bit packages (Wine needs i386) and install the runtime dependencies.
#  - wine / wine32 / wine64 : run the Windows server binaries
#  - winbind                : NTLM/RPC support some installers expect
#  - xvfb                   : virtual X display (Wine GUI apps need a display, even headless)
#  - xdotool                : drive the one-time CD-key dialog without a real desktop
#  - p7zip-full             : extract the .img / .zip distribution archives
#  - cabextract             : winetricks dependency for some redistributables
#  - nodejs                 : runs start-game.mjs (POSTs to the FS25 web portal)
#  - netcat-openbsd, procps, ca-certificates, tini, gosu : helpers + clean PID1
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wine wine32 wine64 winbind \
      xvfb xdotool \
      p7zip-full cabextract \
      nodejs \
      netcat-openbsd procps curl ca-certificates tini gosu locales tzdata \
 && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC

# Create the unprivileged user Pterodactyl/Calagopus expect.
RUN useradd -m -d /home/container -s /bin/bash container

# Runtime logic baked into the image (versioned with the yolk, not the server files).
COPY entrypoint.sh /entrypoint.sh
COPY start.sh /opt/fs25/start.sh
COPY lib/ /opt/fs25/lib/
COPY config/ /opt/fs25/config/
RUN chmod +x /entrypoint.sh /opt/fs25/start.sh /opt/fs25/lib/*.sh

LABEL org.opencontainers.image.source="https://github.com/nn-home-com/farming-simulator-25-egg"

USER container
ENV HOME=/home/container \
    USER=container
WORKDIR /home/container

# Forward SIGINT to the server so the stop handler in start.sh can shut down cleanly.
STOPSIGNAL SIGINT

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
