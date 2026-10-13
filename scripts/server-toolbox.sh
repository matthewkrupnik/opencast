#!/usr/bin/env bash
# Run a command (or a shell) in the Server toolbox container, with the
# repository mounted at /work and Cloudflare credentials from
# Server/Toolbox/cloudflare.env. Examples:
#   scripts/server-toolbox.sh
#   scripts/server-toolbox.sh yarn install --immutable
#   scripts/server-toolbox.sh yarn wrangler whoami
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
image="opencast-server-toolbox"

docker build --quiet --tag "$image" "$root/Server/Toolbox" >/dev/null

# Start in the matching directory when invoked from inside the repository.
workdir="/work"
case "$PWD/" in
  "$root"/*) workdir="/work${PWD#"$root"}" ;;
esac

args=(--rm --workdir "$workdir" --volume "$root:/work"
  --volume opencast-toolbox-cargo-registry:/root/.cargo/registry
  --volume opencast-toolbox-yarn:/root/.yarn/berry
  --volume opencast-toolbox-cache:/root/.cache)
env_file="$root/Server/Toolbox/cloudflare.env"
if [[ -f "$env_file" ]]; then
  args+=(--env-file "$env_file")
fi
if [[ -t 0 && -t 1 ]]; then
  args+=(--interactive --tty)
fi

exec docker run "${args[@]}" "$image" "$@"
