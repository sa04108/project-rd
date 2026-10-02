#!/usr/bin/env bash
set -euo pipefail
# 저장소 지침의 검증 진입점을 실제 게임 검사에 연결한다.
exec bash "$(dirname "${BASH_SOURCE[0]}")/mvp-check.sh" "$@"
