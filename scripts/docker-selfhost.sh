#!/usr/bin/env bash
#
# Build the source-based self-hosting images one at a time, then start the
# stack. `docker compose build` builds independent services concurrently by
# default, which can make the frontend and backend Node builds exceed a small
# server's available memory when they overlap.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/docker-compose.self-hosting.yml")

"${COMPOSE[@]}" build backend
"${COMPOSE[@]}" build frontend
"${COMPOSE[@]}" up -d --no-build
