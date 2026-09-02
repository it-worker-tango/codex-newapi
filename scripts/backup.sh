#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$project_dir/backups"
stage_dir="$(mktemp -d)"
archive="$backup_dir/codex-newapi-$timestamp.tar.gz"
trap 'rm -rf "$stage_dir"' EXIT

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

cd "$project_dir"
docker compose exec -T postgres pg_dump -U newapi -d newapi -Fc > "$stage_dir/newapi.dump"
cp .env compose.yaml "$stage_dir/"
cp -R data/cliproxy data/wireguard "$stage_dir/"

tar -C "$stage_dir" -czf "$archive" .
chmod 600 "$archive"
echo "Backup created: $archive"
echo "This archive contains secrets. Encrypt it before off-site storage."
