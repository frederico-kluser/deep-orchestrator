#!/usr/bin/env bash
# =============================================================================
# check-brave-credits.sh — Verifica saldo de créditos da Brave Search API
# -----------------------------------------------------------------------------
# Faz uma query mínima (q=test, count=1) e lê os créditos dos headers de
# resposta (X-Credit-Remaining ou o 2º valor de X-RateLimit-Remaining =
# quota mensal restante) e o billing-status.
#
# Uso:
#   check-brave-credits.sh [OPTS]
#
# Status: CREDITS_OK | CREDITS_LOW (<100) | NO_CREDITS (0) | CREDITS_UNKNOWN |
#         RATE_LIMITED | CONFIG_ERROR
#
# Exit codes:
#   0 = tem créditos (CREDITS_OK/CREDITS_LOW/CREDITS_UNKNOWN/RATE_LIMITED)
#   1 = sem créditos (NO_CREDITS) ou, com --fail-fast, status CREDITS_LOW/CREDITS_UNKNOWN
#   2 = erro de configuração (BRAVE_API_KEY ausente/inválida, rede, tools)
# =============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
API_URL="${BRAVE_API_URL:-https://api.search.brave.com/res/v1/web/search}"
DEFAULT_TIMEOUT=15
LOW_THRESHOLD=100

JSON_OUT=0
FAIL_FAST=0
TIMEOUT="$DEFAULT_TIMEOUT"

usage() {
  cat <<EOF
Uso: $SCRIPT_NAME [OPTS]

Verifica o saldo de créditos da Brave Search API com uma query mínima
(q=test, count=1). Sem argumentos posicionais.

OPÇÕES
  --json         Saída em JSON parseável (sem texto em stdout)
  --fail-fast    Exit 1 se o status != CREDITS_OK (para o orquestrador)
  --timeout N    Timeout da chamada em segundos (default $DEFAULT_TIMEOUT)
  -h, --help     Mostra esta ajuda

AMBIENTE
  BRAVE_API_KEY   Chave da Brave Search API (obrigatória)
  BRAVE_API_URL   Override do endpoint (uso interno/testes)

STATUS
  CREDITS_OK      Créditos >= $LOW_THRESHOLD
  CREDITS_LOW     Créditos > 0 e < $LOW_THRESHOLD
  NO_CREDITS      Créditos zerados ou problema de faturamento (402/403)
  CREDITS_UNKNOWN Sem header de créditos na resposta
  RATE_LIMITED    HTTP 429 (rate limit atingido; não confirma créditos)
  CONFIG_ERROR    Chave ausente/inválida, rede ou ferramentas

EXIT CODES
  0 tem créditos · 1 sem créditos (ou --fail-fast) · 2 erro de configuração
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --json)      JSON_OUT=1; shift ;;
      --fail-fast) FAIL_FAST=1; shift ;;
      --timeout)   TIMEOUT="$2"; shift 2 ;;
      --timeout=*) TIMEOUT="${1#*=}"; shift ;;
      -*)
        echo "ERRO: flag desconhecida: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        echo "ERRO: argumento posicional não esperado: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done
}

# header_val <arquivo-headers> <nome> → valor do header (ou vazio; sempre exit 0)
header_val() {
  local f="$1" name="$2"
  grep -i "^${name}:" "$f" 2>/dev/null \
    | head -n 1 \
    | cut -d: -f2- \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\r$//' \
    || true
}

# credits_from_headers <arquivo-headers> → créditos restantes (ou vazio)
credits_from_headers() {
  local f="$1" v m
  v="$(header_val "$f" "X-Credit-Remaining")"
  if [[ -n "$v" ]] && [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "$v"
    return
  fi
  v="$(header_val "$f" "X-RateLimit-Remaining")"
  if [[ -n "$v" ]]; then
    m="$(echo "$v" | awk -F, '{ if (NF >= 2) { gsub(/[^0-9]/, "", $2); print $2 } else { gsub(/[^0-9]/, "", $1); print $1 } }')"
    if [[ -n "$m" ]] && [[ "$m" =~ ^[0-9]+$ ]]; then
      echo "$m"
      return
    fi
  fi
  echo ""
}

api_error_message() { # <arquivo-body> → mensagem de erro da API (ou vazio)
  local f="$1"
  jq -r '.message // .error.message // .error // .type // empty' "$f" 2>/dev/null | head -n 1 || true
}

main() {
  parse_args "$@"

  if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || (( TIMEOUT < 1 || TIMEOUT > 120 )); then
    echo "CONFIG_ERROR: --timeout deve ser um inteiro entre 1 e 120 (recebido: '$TIMEOUT')" >&2
    exit 2
  fi
  for bin in curl jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "CONFIG_ERROR: '$bin' não encontrado no PATH (necessário para $SCRIPT_NAME)." >&2
      exit 2
    fi
  done
  if [[ -z "${BRAVE_API_KEY:-}" ]]; then
    echo "CONFIG_ERROR: BRAVE_API_KEY não está definida. Exporte a chave da Brave Search API." >&2
    exit 2
  fi

  local body headers curl_err http_code rc
  body="$(mktemp)"
  headers="$(mktemp)"
  curl_err="$(mktemp)"
  trap 'rm -f "$body" "$headers" "$curl_err"' EXIT

  set +e
  http_code="$(curl -sS --max-time "$TIMEOUT" -G "$API_URL" \
    -H "Accept: application/json" \
    -H "Accept-Encoding: gzip" \
    -H "X-Subscription-Token: ${BRAVE_API_KEY}" \
    --compressed \
    --data-urlencode "q=test" \
    --data-urlencode "count=1" \
    -D "$headers" \
    -o "$body" \
    -w '%{http_code}' 2>"$curl_err")"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "CONFIG_ERROR: falha de rede ao chamar a Brave API (curl exit $rc): $(cat "$curl_err")" >&2
    exit 2
  fi

  local credits rate_remaining rate_reset billing
  credits="$(credits_from_headers "$headers")"
  rate_remaining="$(header_val "$headers" "X-RateLimit-Remaining")"
  rate_reset="$(header_val "$headers" "X-RateLimit-Reset")"
  billing="$(header_val "$headers" "billing-status")"

  local status detail
  case "${http_code:-}" in
    200)
      if [[ -n "$credits" ]] && [[ "$credits" =~ ^[0-9]+$ ]]; then
        if (( credits == 0 )); then
          status="NO_CREDITS"
          detail="saldo zerado (0 créditos restantes)"
        elif (( credits < LOW_THRESHOLD )); then
          status="CREDITS_LOW"
          detail="${credits} créditos restantes (< ${LOW_THRESHOLD})"
        else
          status="CREDITS_OK"
          detail="${credits} créditos restantes"
        fi
      else
        status="CREDITS_UNKNOWN"
        detail="API respondeu 200 mas nenhum header de créditos encontrado"
      fi
      ;;
    401)
      status="CONFIG_ERROR"
      detail="chave inválida (HTTP 401) — confira BRAVE_API_KEY"
      ;;
    402|403)
      status="NO_CREDITS"
      detail="problema de faturamento (HTTP ${http_code}): $(api_error_message "$body")"
      ;;
    429)
      status="RATE_LIMITED"
      detail="rate limit atingido (HTTP 429); reset: ${rate_reset:-desconhecido}"
      ;;
    *)
      status="CREDITS_UNKNOWN"
      detail="resposta inesperada (HTTP ${http_code}): $(api_error_message "$body")"
      ;;
  esac

  local exit_code=0
  case "$status" in
    NO_CREDITS)   exit_code=1 ;;
    CONFIG_ERROR) exit_code=2 ;;
    CREDITS_OK|RATE_LIMITED) exit_code=0 ;;
    *)
      # CREDITS_LOW/CREDITS_UNKNOWN: falham apenas com --fail-fast
      if (( FAIL_FAST )); then exit_code=1; fi
      ;;
  esac

  if (( JSON_OUT )); then
    jq -n \
      --arg status "$status" \
      --arg detail "$detail" \
      --argjson credits "${credits:-null}" \
      --argjson http "${http_code:-null}" \
      --arg rate_limit_limit "$(header_val "$headers" "X-RateLimit-Limit")" \
      --arg rate_limit_remaining "$rate_remaining" \
      --arg rate_limit_reset "$rate_reset" \
      --arg billing_status "$billing" \
      '{status: $status, detail: $detail, credits_remaining: $credits, http_status: $http, rate_limit_limit: $rate_limit_limit, rate_limit_remaining: $rate_limit_remaining, rate_limit_reset: $rate_limit_reset, billing_status: $billing_status}'
  else
    echo "$status — $detail"
    if [[ -n "$rate_remaining" ]]; then
      echo "Rate limit restante: $rate_remaining (reset: ${rate_reset:-?}s)"
    fi
    [[ -n "$billing" ]] && echo "Billing status: $billing"
  fi

  exit "$exit_code"
}

main "$@"
