#!/bin/bash

##
# ONETIME ENTRYPOINT SCRIPT - 2024-05-18 (injects SITE_SECRET into config.yaml)
#

set -e

PORT=${PORT:-3000}
SERVER_TYPE=${SERVER_TYPE:-thin}
PUMA_MIN_THREADS=${PUMA_MIN_THREADS:-4}
PUMA_MAX_THREADS=${PUMA_MAX_THREADS:-16}
PUMA_WORKERS=${PUMA_WORKERS:-2}

if [ "$ONETIME_DEBUG" = "true" ] || [ "$ONETIME_DEBUG" = "1" ]; then
  set -x
fi

datestamp=$(date -u)
location=$(readlink -f "${0}")
basename=$(basename "${location}")

>&2 echo "[${datestamp}] INFO: Running ${basename}..."
unset datestamp location basename

# ✅ Inject SITE_SECRET into etc/config.yaml
if [ -n "$SITE_SECRET" ]; then
  >&2 echo "[entrypoint] Injecting SITE_SECRET into etc/config.yaml..."
  sed -i "s/^\(\s*:secret:\).*/\1 $SITE_SECRET/" etc/config.yaml
else
  >&2 echo "[entrypoint] WARNING: SITE_SECRET is not set; using existing config.yaml value."
fi

# Optionally install gems at runtime
if [[ "${BUNDLE_INSTALL,,}" == "true" ]]; then
  >&2 echo "Running bundle install..."
  bundle install
else
  >&2 echo "Skipping bundle install. Use BUNDLE_INSTALL=true to run it."
fi

# Optional static asset mount
if [ -d "/mnt/public" ]; then
  cp -r public/web /mnt/public/
fi

# Start server
if [ $# -eq 0 ]; then
  if [ "$SERVER_TYPE" = "puma" ]; then
    >&2 echo "Starting Puma server on port $PORT with $PUMA_WORKERS workers ($PUMA_MIN_THREADS-$PUMA_MAX_THREADS threads)"
    RUBY_YJIT_ENABLE=1 exec bundle exec puma -R config.ru -p $PORT -t $PUMA_MIN_THREADS:$PUMA_MAX_THREADS -w $PUMA_WORKERS
  else
    >&2 echo "Starting Thin server on port $PORT"
    exec bundle exec thin -R config.ru -p $PORT start
  fi
else
  exec bundle exec "$@"
fi
