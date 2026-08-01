#!/usr/bin/env bash

set -euo pipefail

vp fmt --check packages tests scripts docs .github
vp lint --import-plugin --deny-warnings --type-aware --tsconfig tsconfig.dev.json packages tests scripts docs .github
vp install --frozen-lockfile --ignore-scripts -- \
  --config.confirmModulesPurge=false \
  --config.side-effects-cache=false \
  --config.verify-store-integrity=true \
  --config.strict-store-pkg-content-check=true \
  --config.package-import-method=clone-or-copy \
  --pm-on-fail=ignore
vp exec madge --circular --no-spinner examples/*/src packages/*/*/src

(cd docs && bash scripts/check-md-imports.sh)
