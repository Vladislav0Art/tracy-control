#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
mkdir -p "${ARTIFACTS_DIR}"

clone_if_missing() {
  local url="$1" dest="$2"
  if [ -d "${dest}/.git" ]; then
    echo "Skipping clone: ${dest} already exists."
  else
    echo "Cloning ${url} -> ${dest}"
    git clone "${url}" "${dest}"
  fi
}

clone_if_missing "https://github.com/JetBrains/codespheres-evaluator-api-coverage" "${ARTIFACTS_DIR}/evaluator"
clone_if_missing "https://github.com/slawa4s/codespheres-tracy" "${ARTIFACTS_DIR}/tracy"

cat <<'EOF'

Done. Next steps:
  1. Create a .env file in the repo root containing:
       ANTHROPIC_BASE_URL=...
       ANTHROPIC_AUTH_TOKEN=...
  2. Build the image:
       docker build -t local-tracy-evaluation-control .
  3. Run it (see README.md for the full docker run command).
EOF
