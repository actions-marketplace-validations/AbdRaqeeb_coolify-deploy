#!/usr/bin/env bash
set -eu
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=print-message.sh
source "${SCRIPT_DIR}/print-message.sh"

BASE_URL=''
APP_ID=''
TOKEN="${TOKEN:-}"
GITHUB_OUTPUT_FILE="${GITHUB_OUTPUT:-}"

DEPLOY_RESPONSE_FILE="${TMPDIR:-/tmp}/03_deploy_post.json"

print_usage() {
    cat <<'EOF'
Usage: 03-deploy-app.sh --baseUrl <url> --appId <id> [options]

Required:
  --baseUrl, --base-url   API base URL
  --appId, --app-id       Application ID

Options:
  --token                 Bearer token (optional; TOKEN env also works)
  --githubOutput, --github-output
                          GitHub Actions step output file (default: GITHUB_OUTPUT env; else stdout)
  -h, --help              Show this help

Example:
  03-deploy-app.sh --baseUrl 'https://api.example.com' --appId 'xyz'
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h | --help)
                print_usage
                exit 0
                ;;
            --baseUrl | --base-url)
                BASE_URL="${2:-}"
                shift 2
                ;;
            --baseUrl=* | --base-url=*)
                BASE_URL="${1#*=}"
                shift
                ;;
            --appId | --app-id)
                APP_ID="${2:-}"
                shift 2
                ;;
            --appId=* | --app-id=*)
                APP_ID="${1#*=}"
                shift
                ;;
            --token)
                TOKEN="${2:-}"
                shift 2
                ;;
            --token=*)
                TOKEN="${1#*=}"
                shift
                ;;
            --githubOutput | --github-output)
                GITHUB_OUTPUT_FILE="${2:-}"
                shift 2
                ;;
            --githubOutput=* | --github-output=*)
                GITHUB_OUTPUT_FILE="${1#*=}"
                shift
                ;;
            *)
                print_message ERROR "Unknown argument: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

validate_inputs() {
    if [[ -z "${BASE_URL}" ]]; then
        print_message ERROR "Missing required --baseUrl"
        print_usage
        exit 1
    fi
    if [[ -z "${APP_ID}" ]]; then
        print_message ERROR "Missing required --appId"
        print_usage
        exit 1
    fi
}

deploy_start_url() {
    echo "${BASE_URL%/}/api/v1/applications/${APP_ID}/start"
}

append_curl_auth() {
    local -n _args=$1
    if [[ -n "${TOKEN}" ]]; then
        _args+=(-H "Authorization: Bearer ${TOKEN}")
    fi
}

write_http_code_output() {
    local code=$1
    if [[ -n "${GITHUB_OUTPUT_FILE}" ]]; then
        {
            echo "http_code=${code}"
        } >>"${GITHUB_OUTPUT_FILE}"
    else
        echo "http_code=${code}"
    fi
}

write_deployment_uuid_output() {
    local uuid=$1
    if [[ -n "${GITHUB_OUTPUT_FILE}" ]]; then
        {
            echo "deployment_uuid=${uuid}"
        } >>"${GITHUB_OUTPUT_FILE}"
    else
        echo "deployment_uuid=${uuid}"
    fi
}

trigger_deploy() {
    local url code msg uuid
    url=$(deploy_start_url)
    print_message INFO "Deploying image: POST ${url}"

    local curl_args=(-sS -H "Accept: application/json")
    append_curl_auth curl_args

    if ! code=$(curl "${curl_args[@]}" -X POST -o "${DEPLOY_RESPONSE_FILE}" -w "%{http_code}" "$url"); then
        print_message ERROR "curl failed for POST ${url}"
        exit 1
    fi

    write_http_code_output "${code}"

    if [[ "${code}" != "200" ]]; then
        print_message ERROR "Deploy not accepted or unexpected status (HTTP ${code})"
        log_api_response_body "${DEPLOY_RESPONSE_FILE}"
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        print_message ERROR "jq is required to read deployment_uuid from deploy response"
        exit 1
    fi
    if [[ ! -s "${DEPLOY_RESPONSE_FILE}" ]] || ! jq -e . >/dev/null 2>&1 <"${DEPLOY_RESPONSE_FILE}"; then
        print_message ERROR "Deploy response is empty or not valid JSON"
        log_api_response_body "${DEPLOY_RESPONSE_FILE}"
        exit 1
    fi

    msg=$(jq -r '.message // empty' "${DEPLOY_RESPONSE_FILE}")
    uuid=$(jq -r '.deployment_uuid // empty' "${DEPLOY_RESPONSE_FILE}")

    if [[ -n "${msg}" ]]; then
        print_message INFO "${msg}"
    fi
    if [[ -z "${uuid}" ]]; then
        print_message ERROR "deploy response missing deployment_uuid"
        log_api_response_body "${DEPLOY_RESPONSE_FILE}"
        exit 1
    fi

    print_message INFO "deployment_uuid: ${uuid}"
    write_deployment_uuid_output "${uuid}"
}

main() {
    parse_args "$@"
    validate_inputs
    trigger_deploy
}

main "$@"
