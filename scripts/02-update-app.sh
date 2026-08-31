#!/usr/bin/env bash
set -eu
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=print-message.sh
source "${SCRIPT_DIR}/print-message.sh"

BASE_URL=''
APP_ID=''
IMAGE_TAG=''
TOKEN="${TOKEN:-}"
GITHUB_OUTPUT_FILE="${GITHUB_OUTPUT:-}"

print_usage() {
    cat <<'EOF'
Usage: 02-update-app.sh --baseUrl <url> --appId <id> --imageTag <sha|tag> [options]

Required:
  --baseUrl, --base-url     API base URL
  --appId, --app-id         Application ID
  --imageTag, --image-tag   Value for docker_registry_image_tag (e.g. commit SHA)

Options:
  --token                   Bearer token (optional; TOKEN env also works)
  --githubOutput, --github-output
                            GitHub Actions step output file (default: GITHUB_OUTPUT env; else stdout)
  -h, --help                Show this help

Example:
  02-update-app.sh --baseUrl 'https://api.example.com' --appId 'xyz' --imageTag 'abc123'
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
            --imageTag | --image-tag)
                IMAGE_TAG="${2:-}"
                shift 2
                ;;
            --imageTag=* | --image-tag=*)
                IMAGE_TAG="${1#*=}"
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
    if [[ -z "${IMAGE_TAG}" ]]; then
        print_message ERROR "Missing required --imageTag"
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

patch_docker_image_tag() {
    local url body code
    url=$(application_url)
    body=$(jq -nc --arg tag "${IMAGE_TAG}" '{docker_registry_image_tag: $tag}')

    print_message INFO "Updating docker_registry_image_tag to '${IMAGE_TAG}': PATCH ${url}"

    local curl_args=(
        -sS
        -H "Content-Type: application/json"
        -H "Accept: application/json"
    )
    append_curl_auth curl_args

    if ! code=$(curl "${curl_args[@]}" -X PATCH -o /tmp/02_patch_app.json -d "${body}" -w "%{http_code}" "$url"); then
        print_message ERROR "curl failed for PATCH ${url}"
        exit 1
    fi

    write_http_code_output "${code}"

    if [[ "${code}" == "200" ]]; then
        print_message INFO "Image tag updated (HTTP ${code})"
    else
        print_message ERROR "Image tag update failed or unexpected status (HTTP ${code})"
        log_api_response_body /tmp/02_patch_app.json
        exit 1
    fi
}

main() {
    parse_args "$@"
    validate_inputs
    patch_docker_image_tag
}

main "$@"
