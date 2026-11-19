#!/usr/bin/env bash
set -Eeuo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/export_casino_handover.sh" "$@"
