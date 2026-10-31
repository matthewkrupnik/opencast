#!/usr/bin/env bash
# Provision and deploy the production notifications lane (NotificationsWorker
# + FeedPollingWorker) from their git-ignored wrangler.production.* configs.
# Safe to re-run: resources that already exist are kept. Run it in the
# toolbox from the repository root:
#   scripts/server-toolbox.sh Server/Toolbox/deploy-production.sh
set -euo pipefail

root=/work
notifications_dir="$root/Server/NotificationsWorker"
polling_dir="$root/Server/FeedPollingWorker"
notifications_config=wrangler.production.toml
polling_config=wrangler.production.jsonc
apns_dir="$root/Server/Toolbox/apns"
bucket=opencast-feed-snapshots
placeholder=REPLACE_WITH_APNS_MTLS_CERTIFICATE_ID
# Supabase's root CA, from the project's Database settings.
pg_ca="$root/Server/Toolbox/prod-ca-2021.crt"

step() { printf '\n==> %s\n' "$*"; }
wrangler() { "$root/node_modules/.bin/wrangler" "$@"; }
# psql as the schema owner. The Workers connect as the runtime role through Hyperdrive.
pg_owner() { psql "$OPENCAST_PG_OWNER_URL?sslmode=verify-full&sslrootcert=$pg_ca" -X -v ON_ERROR_STOP=1 "$@"; }

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo "Set CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID in Server/Toolbox/cloudflare.env." >&2
  exit 1
fi
if [[ -z "${OPENCAST_PG_OWNER_URL:-}" || ! -f "$pg_ca" ]]; then
  echo "Set OPENCAST_PG_OWNER_URL in Server/Toolbox/cloudflare.env and put prod-ca-2021.crt in Server/Toolbox/." >&2
  exit 1
fi
for config in "$notifications_dir/$notifications_config" "$polling_dir/$polling_config"; do
  [[ -f "$config" ]] || { echo "Missing $config" >&2; exit 1; }
done

if [[ ! -d "$root/node_modules/wrangler" ]]; then
  step "Installing dependencies"
  (cd "$root" && yarn install --immutable)
fi

if grep -q "$placeholder" "$notifications_dir/$notifications_config"; then
  step "Uploading the APNs certificate"
  if [[ ! -f "$apns_dir/apns-cert.pem" || ! -f "$apns_dir/apns-key.pem" ]]; then
    echo "Put apns-cert.pem and apns-key.pem in Server/Toolbox/apns/ first." >&2
    exit 1
  fi
  # APNs rejects the handshake unless the Apple WWDR G4 intermediate follows
  # the leaf, and Cloudflare then answers every send with an empty 500.
  chain="$(mktemp)"
  openssl x509 -in "$apns_dir/apns-cert.pem" >"$chain"
  curl -fsS https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer | openssl x509 -inform der >>"$chain"
  output="$(wrangler mtls-certificate upload \
    --cert "$chain" --key "$apns_dir/apns-key.pem" --name opencast-apns-production 2>&1)"
  rm -f "$chain"
  echo "$output"
  certificate_id="$(sed -n 's/^ID: *//p' <<<"$output" | head -1)"
  if [[ -z "$certificate_id" ]]; then
    echo "Couldn't read the certificate ID from the output above." >&2
    exit 1
  fi
  sed -i "s/$placeholder/$certificate_id/" "$notifications_dir/$notifications_config"
fi

step "R2 bucket $bucket"
wrangler r2 bucket info "$bucket" >/dev/null 2>&1 || wrangler r2 bucket create "$bucket"

# Dead-letter queues first: the main queues' consumers point at them.
for kind in event episode job poll; do
  for queue in "opencast-notification-$kind-production-dlq" "opencast-notification-$kind-production"; do
    step "Queue $queue"
    wrangler queues info "$queue" >/dev/null 2>&1 || wrangler queues create "$queue"
  done
done

cd "$notifications_dir"

# The schema is applied once by hand (postgres/README.md's single-runtime-role
# order); migration files are immutable, so a deploy only checks it is there.
step "PostgreSQL schema"
schema_tables="$(pg_owner -At -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'opencast'")"
if [[ "$schema_tables" != 32 ]]; then
  echo "Expected 32 tables in schema opencast, found $schema_tables. Apply Server/NotificationsWorker/postgres first." >&2
  exit 1
fi

step "Deploying opencast-notifications"
wrangler deploy --config "$notifications_config"

if ! wrangler secret list --config "$notifications_config" 2>/dev/null | grep -q CHALLENGE_SOURCE_HASH_KEY; then
  step "Setting CHALLENGE_SOURCE_HASH_KEY"
  openssl rand -base64 32 | tr -d '\n' | wrangler secret put CHALLENGE_SOURCE_HASH_KEY --config "$notifications_config"
fi

# The database half of the dual switch; the wrangler vars are the other half.
step "Opening the new-episode n_control rows"
pg_owner -c "UPDATE opencast.n_control SET enabled=1, revision=revision+1 WHERE enabled=0 AND name IN \
   ('dispatcher_admission','feed_observation','episode_activation','episode_send','cleanup')"

cd "$polling_dir"
step "Deploying opencast-feed-polling"
wrangler deploy --config "$polling_config"

step "Done"
echo "Notifications server: https://opencast-notofications.mkcs.dev"
