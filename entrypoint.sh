#!/bin/bash
set -e

PUID=${PUID:-1000}
PGID=${PGID:-100}
RENDER_GID=${RENDER_GID:-992}
TZ=${TZ:-UTC}

ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
echo $TZ > /etc/timezone

userdel -r ubuntu 2>/dev/null || true

CURRENT_UID=$(id -u lizard)
CURRENT_GID=$(id -g lizard)

if [ "$CURRENT_UID" != "$PUID" ]; then
    usermod -o -u "$PUID" lizard
fi
if [ "$CURRENT_GID" != "$PGID" ]; then
    usermod -g "$PGID" lizard
fi

groupadd -o -g "$RENDER_GID" rendergroup 2>/dev/null || true
usermod -aG rendergroup lizard
usermod -aG input lizard

chown -R "$PUID":"$PGID" /home/lizard
find /games ! -user "$PUID" -exec chown "$PUID":"$PGID" {} + 2>/dev/null || true

/lib/systemd/systemd-udevd --daemon || true
sleep 1

rm -f /tmp/.X1-lock
rm -rf /tmp/.X11-unix
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

export DISPLAY=:1
export HOME=/home/lizard

gosu lizard Xorg -noreset -novtswitch -sharevts -config /etc/X11/xorg-dummy.conf :1 &
sleep 3

: > /home/lizard/fluxbox.log
chown "$PUID":"$PGID" /home/lizard/fluxbox.log
gosu lizard bash -c '
while true; do
    fluxbox >> /home/lizard/fluxbox.log 2>&1
    echo "$(date "+%F %T"): fluxbox exited, restarting in 2s" >> /home/lizard/fluxbox.log
    sleep 2
done
' &
sleep 1

export XDG_RUNTIME_DIR=/run/user/$PUID
mkdir -p $XDG_RUNTIME_DIR
chown $PUID:$PGID $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

gosu lizard pulseaudio --start --exit-idle-time=-1 --disallow-exit || true
sleep 2
gosu lizard pactl load-module module-null-sink sink_name=virtual_speaker sink_properties=device.description=VirtualSpeaker || true
gosu lizard pactl set-default-sink virtual_speaker || true

: > /home/lizard/dbgl.log
chown "$PUID":"$PGID" /home/lizard/dbgl.log
gosu lizard bash -c '
while true; do
    SWT_GTK3=0 java -Djdk.util.zip.disableZip64ExtraFieldValidation=true -Djava.library.path=lib -Ddbgl.data.userhome=true -jar /opt/dbgl/dbgl.jar >> /home/lizard/dbgl.log 2>&1
    echo "$(date "+%F %T"): dbgl exited, restarting in 3s" >> /home/lizard/dbgl.log
    sleep 3
done
' &

exec gosu lizard sunshine
