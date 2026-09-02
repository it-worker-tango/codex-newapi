#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
"$project_dir/scripts/backup.sh"
docker compose pull
docker compose up -d --remove-orphans
docker compose ps
