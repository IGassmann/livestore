#!/usr/bin/env bash

set -euo pipefail

vp exec tsc --build tsconfig.dev.json
