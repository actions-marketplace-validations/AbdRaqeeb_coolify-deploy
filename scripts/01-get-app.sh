#!/usr/bin/env bash
set -eu
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=print-message.sh
source "${SCRIPT_DIR}/print-message.sh"

BASE_URL=''
APP_ID=''
NEW_IMAGE_TAG="${NEW_IMAGE_TAG:-}"
TOKEN="${TOKEN:-}"
GITHUB_OUTPUT_FILE="${GITHUB_OUTPUT:-}"

print_usage() {
    cat <<'EOF'
Usage: 01-get-app.sh --baseUrl <url> --appId <id> [options]

Required:
  --baseUrl, --base-url   API base URL (no trailing slash required)
  --appId, --app-id       Application ID

Options:
  --newImageTag, --new-image-tag
                          Tag you intend to deploy (e.g. commit SHA); shown next to current tag from API
  --token                 Bearer token (optional; TOKEN env also works)
  --githubOutput, --github-output
                          GitHub Actions step output file (default: GITHUB_OUTPUT env; else stdout)
  -h, --help              Show this help

Example:
  01-get-app.sh --baseUrl 'https://api.example.com' --appId 'xyz' --newImageTag 'abc123def'
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
            --newImageTag | --new-image-tag)
                NEW_IMAGE_TAG="${2:-}"
                shift 2
                ;;
            --newImageTag=* | --new-image-tag=*)
                NEW_IMAGE_TAG="${1#*=}"
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

application_url() {
    echo "${BASE_URL%/}/api/v1/applications/${APP_ID}"
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

GET_APP_RESPONSE_FILE="${TMPDIR:-/tmp}/01_get_app.json"

print_app_name_and_image_tags() {
    local body_file=$1
    if ! command -v jq >/dev/null 2>&1; then
        print_message WARN "jq not installed; cannot show name / image tags"
        return 0
    fi
    if [[ ! -s "${body_file}" ]] || ! jq -e . >/dev/null 2>&1 <"${body_file}"; then
        print_message WARN "Empty or invalid JSON in response body"
        return 0
    fi
    local name current_tag new_tag
    name=$(jq -r '.name // "n/a"' "${body_file}")
    current_tag=$(jq -r '.docker_registry_image_tag // "n/a"' "${body_file}")
    new_tag="${NEW_IMAGE_TAG:-n/a}"
    print_message INFO "Application name: ${name}"
    print_message INFO "Current image tag: ${current_tag}"
    print_message INFO "New image tag: ${new_tag}"
}

fetch_application() {
    local url code
    url=$(application_url)
    print_message INFO "Fetching app: GET ${url}"

    local curl_args=(-sS)
    append_curl_auth curl_args

    if ! code=$(curl "${curl_args[@]}" -o "${GET_APP_RESPONSE_FILE}" -w "%{http_code}" "$url"); then
        print_message ERROR "curl failed for GET ${url}"
        exit 1
    fi

    write_http_code_output "${code}"

    if [[ "${code}" == "200" ]]; then
        print_app_name_and_image_tags "${GET_APP_RESPONSE_FILE}"
        print_message INFO "App is available (HTTP ${code})"
    else
        print_message ERROR "App not available or unexpected status (HTTP ${code})"
        log_api_response_body "${GET_APP_RESPONSE_FILE}"
        exit 1
    fi
}

main() {
    parse_args "$@"
    validate_inputs
    fetch_application
}

main "$@"
