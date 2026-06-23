#!/bin/bash
# Pterodactyl/Calagopus-style entrypoint.
#
# Wings starts this container and passes the parsed startup command from the egg
# through the $STARTUP environment variable. We substitute any remaining {{VAR}}
# placeholders with their environment values and then exec the result, so the real
# server process replaces this shell and receives stop signals directly.
cd /home/container || exit 1

# Show the Wine version once for support/debugging.
echo "container@fs25:~$ wine --version"
wine --version || true

# Expand {{VAR}} placeholders that Wings leaves in $STARTUP.
MODIFIED_STARTUP=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
eval MODIFIED_STARTUP="\"${MODIFIED_STARTUP}\""

echo "container@fs25:~$ ${MODIFIED_STARTUP}"
exec env MODIFIED_STARTUP="${MODIFIED_STARTUP}" bash -c "${MODIFIED_STARTUP}"
