#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$project_dir/.env"
example_file="$project_dir/.env.example"

command -v openssl >/dev/null || { echo "Error: openssl is required." >&2; exit 1; }

if [[ ! -f "$env_file" ]]; then
  cp "$example_file" "$env_file"
  echo "Created .env from .env.example"
fi

replace_if_empty() {
  local key="$1" value
  value="$(openssl rand -hex 32)"
  if grep -qE "^${key}=$" "$env_file"; then
    sed -i.bak "s|^${key}=$|${key}=${value}|" "$env_file"
  elif ! grep -qE "^${key}=" "$env_file"; then
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

for key in POSTGRES_PASSWORD REDIS_PASSWORD SESSION_SECRET CPA_API_KEY CPA_MANAGEMENT_KEY; do
  replace_if_empty "$key"
done
rm -f "$env_file.bak"
chmod 600 "$env_file"

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

if [[ -z "${SERVER_PUBLIC_IP:-}" || "$SERVER_PUBLIC_IP" == "203.0.113.10" ]]; then
  echo "Error: set SERVER_PUBLIC_IP in .env before deployment." >&2
  exit 1
fi

mkdir -p \
  "$project_dir/data/wireguard" \
  "$project_dir/data/cliproxy/auths" \
  "$project_dir/data/cliproxy/logs" \
  "$project_dir/data/newapi/logs" \
  "$project_dir/data/postgres" \
  "$project_dir/data/redis" \
  "$project_dir/backups"

config_file="$project_dir/data/cliproxy/config.yaml"
if [[ ! -f "$config_file" ]]; then
  umask 077
  cat > "$config_file" <<EOF
host: 0.0.0.0
port: 8317
auth-dir: /root/.cli-proxy-api
api-keys:
  - "$CPA_API_KEY"
remote-management:
  allow-remote: false
  secret-key: "$CPA_MANAGEMENT_KEY"
EOF
fi

echo "Initialization complete."
echo "Next: docker compose pull && docker compose up -d"
