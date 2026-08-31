#!/usr/bin/env bash
# Source from numbered deploy scripts, e.g.: source "$(dirname "${BASH_SOURCE[0]}")/print-message.sh"

if [[ -n "${NO_COLOR:-}" ]]; then
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
elif [[ -t 1 ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

print_message() {
    local level=$1
    shift
    local msg="$*"
    case "${level}" in
        INFO) echo -e "${BLUE}[INFO]${NC} ${msg}" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} ${msg}" >&2 ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${msg}" >&2 ;;
        *) echo "[${level}] ${msg}" ;;
    esac
}

# Log API error payload to stderr (capped) when GET/PATCH/POST fails or body is invalid.
log_api_response_body() {
    local path=${1:-}
    local max_bytes=${2:-8192}
    if [[ -z "${path}" || ! -f "${path}" || ! -s "${path}" ]]; then
        return 0
    fi
    print_message ERROR "Response body (first ${max_bytes} bytes):"
    head -c "${max_bytes}" "${path}" >&2 || true
    echo >&2
}
