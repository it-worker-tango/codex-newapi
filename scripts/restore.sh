#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: sudo $0 /path/to/codex-newapi-backup.tar.gz" >&2
  exit 1
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT

[[ -f "$archive" ]] || { echo "Backup not found: $archive" >&2; exit 1; }

tar -C "$stage_dir" -xzf "$archive"
cp "$stage_dir/.env" "$project_dir/.env"
mkdir -p "$project_dir/data"
mkdir -p "$project_dir/data/cliproxy" "$project_dir/data/wireguard"
cp -R "$stage_dir/cliproxy/." "$project_dir/data/cliproxy/"
cp -R "$stage_dir/wireguard/." "$project_dir/data/wireguard/"
chmod 600 "$project_dir/.env"

cd "$project_dir"
docker compose up -d postgres redis
until docker compose exec -T postgres pg_isready -U newapi -d newapi >/dev/null 2>&1; do
  sleep 2
done
docker compose exec -T postgres pg_restore -U newapi -d newapi --clean --if-exists < "$stage_dir/newapi.dump"
docker compose up -d
echo "Restore complete. Check with: docker compose ps"
