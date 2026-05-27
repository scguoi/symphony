#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
demo_root="${repo_root}/.demo"
source_repo="${demo_root}/source"
bare_repo="${demo_root}/gitea-repo.git"

rm -rf "${source_repo}" "${bare_repo}"
mkdir -p "${source_repo}"

cat >"${source_repo}/README.md" <<'README'
# ForgeFlow Demo Repository

This repository is used by the local ForgeFlow end-to-end demo.
README

git -C "${source_repo}" init -b main >/dev/null
git -C "${source_repo}" config user.name "ForgeFlow Demo"
git -C "${source_repo}" config user.email "demo@forgeflow.local"
git -C "${source_repo}" add README.md
git -C "${source_repo}" commit -m "chore: seed demo repository" >/dev/null
git clone --bare "${source_repo}" "${bare_repo}" >/dev/null 2>&1

echo "Prepared demo repository at ${bare_repo}"
