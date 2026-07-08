#!/usr/bin/env bash
# generate-spa-auth-config.sh
#
# Build the runtime SPA auth-config JSON ({domain}.json) from a merged
# cdk.context.json. Most VITE_* values are now derived from a single
# PROD_DOMAIN (e.g. lyric.scala.ai); explicit overrides in the context
# file always win, so this is a backwards-compatible change.
#
# Why a separate script (instead of inline bash in action.yml)?
#   - Testable from a shell with fixture inputs (see scripts/test/).
#   - Easier to read / diff than a multi-page heredoc inside YAML.
#
# Inputs (env vars):
#   CONTEXT_FILE   Path to merged cdk.context.json. Required.
#   CDK_ENV        Environment key, e.g. "lyric-prod". Required.
#   CLIENT         Client name, e.g. "lyric". Required.
#   ENV            Environment name, e.g. "prod". Required.
#   OUTPUT_FILE    Path to write the JSON. Defaults to stdout.
#
# Output: writes the JSON config to OUTPUT_FILE (or stdout) and prints
# a one-line summary including the resolved DOMAIN to stderr.

set -euo pipefail

: "${CONTEXT_FILE:?CONTEXT_FILE is required}"
: "${CDK_ENV:?CDK_ENV is required}"
: "${CLIENT:?CLIENT is required}"
: "${ENV:?ENV is required}"

if [ ! -f "$CONTEXT_FILE" ]; then
  echo "::error::cdk.context.json not found at $CONTEXT_FILE" >&2
  exit 1
fi

# ── jq selectors ──────────────────────────────────────────────────────
# VA selects the voyager-app block; CI selects the core-infra block.
# Quoted with a custom delimiter so the embedded "" survives untouched.
VA=".environments[\"$CDK_ENV\"][\"voyager-app\"]"
CI=".environments[\"$CDK_ENV\"][\"core-infra\"]"

# ── helpers ───────────────────────────────────────────────────────────
# read_va FIELD       — read voyager-app.FIELD as a string, "" if null/missing.
# resolve EXPLICIT D  — return EXPLICIT if non-empty/non-null, else D.
# Both are tiny so the per-field call sites stay readable.

read_va() {
  jq -r "$VA.\"$1\" // \"\"" "$CONTEXT_FILE"
}

resolve() {
  local explicit="$1"
  local derived="$2"
  if [ -n "$explicit" ] && [ "$explicit" != "null" ]; then
    echo "$explicit"
  else
    echo "$derived"
  fi
}

# ── DOMAIN + PROD_DOMAIN resolution ───────────────────────────────────
# DOMAIN drives the output filename ("{DOMAIN}.json"); it must always
# come from core-infra.dns_config.domain because that's what the
# CloudFront / Route53 stacks already use.
#
# PROD_DOMAIN drives the URL derivation. By default it's the same as
# DOMAIN, but a client may override it under voyager-app.PROD_DOMAIN
# if the SPA needs to point at a different hostname than its own
# CloudFront serves (rare; mostly useful for preview/playground envs
# that should still hit prod URLs).

DOMAIN=$(jq -r "$CI.dns_config.domain // \"\"" "$CONTEXT_FILE")
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
  echo "::error::domain not found in core-infra.dns_config for environment $CDK_ENV" >&2
  exit 1
fi

PROD_DOMAIN=$(read_va PROD_DOMAIN)
if [ -z "$PROD_DOMAIN" ]; then
  PROD_DOMAIN="$DOMAIN"
fi

# ── derived defaults ──────────────────────────────────────────────────
# Each VITE_* below has the form: explicit-from-context OR derived-from-PROD_DOMAIN.
# This is the heart of VOYAG-409: a config error in any of these
# fields can't drift between envs, because the source of truth is a
# single PROD_DOMAIN value.
#
# Fields NOT in this list (e.g. VITE_OIDC_CLIENT_ID, VITE_OIDC_REDIRECT_URI,
# VITE_GA_MEASUREMENT_ID, VITE_OIDC_ORGANIZATION) are intentionally
# explicit-only — they're per-tenant secrets / IDs that have no
# convention to derive from.

GRAPHQL_URI=$(resolve     "$(read_va VITE_GRAPHQL_URI)"               "https://${PROD_DOMAIN}/graphql")
GRAPHQL_WS_URI=$(resolve  "$(read_va VITE_GRAPHQL_WS_URI)"            "wss://${PROD_DOMAIN}/graphql")
OIDC_AUDIENCE=$(resolve   "$(read_va VITE_OIDC_AUDIENCE)"             "https://${PROD_DOMAIN}/api")
HELP_TICKET_URI=$(resolve "$(read_va VITE_HELP_TICKET_URI)"           "https://${PROD_DOMAIN}/ticket")
ALB_HOSTNAME=$(resolve    "$(read_va VITE_PUBLIC_ALB_HOSTNAME)"       "services.${PROD_DOMAIN}")
RECORDING_URI=$(resolve   "$(read_va VITE_RECORDING_URI)"             "https://${PROD_DOMAIN}/recordings/download")
PULSE_AGENT_BASE_URI=$(resolve "$(read_va PULSE_AGENT_BASE_URI)"     "https://${PROD_DOMAIN}/agent/019e4340-e54c-73ea-8000-0000000000cb")

# Playground variants follow the same pattern but with a "playground."
# subdomain prefix. PREVIEW / PRODUCTION variants stay explicit-only —
# they're rare enough that a convention would be more confusing than
# helpful.
GRAPHQL_URI_PLAYGROUND=$(resolve    "$(read_va VITE_GRAPHQL_URI_PLAYGROUND)"     "https://playground.${PROD_DOMAIN}/graphql")
GRAPHQL_WS_URI_PLAYGROUND=$(resolve "$(read_va VITE_GRAPHQL_WS_URI_PLAYGROUND)"  "wss://playground.${PROD_DOMAIN}/graphql")
RECORDING_URI_PLAYGROUND=$(resolve  "$(read_va VITE_RECORDING_URI_PLAYGROUND)"   "https://playground.${PROD_DOMAIN}/recordings/download")

# ── pure passthrough fields ───────────────────────────────────────────
# No PROD_DOMAIN convention applies; just pull whatever is in context.
OIDC_WELLKNOWN=$(read_va VITE_OIDC_WELLKNOWN_URL)
OIDC_TOKEN=$(read_va VITE_OIDC_TOKEN_URL)
OIDC_USERINFO=$(read_va VITE_OIDC_USERINFO_URL)
OIDC_AUTHORIZE=$(read_va VITE_OIDC_AUTHORIZE_URL)
OIDC_IDP=$(read_va VITE_IDP_CONNECTION_NAME)
OIDC_CLIENT_ID=$(read_va VITE_OIDC_CLIENT_ID)
OIDC_REDIRECT=$(read_va VITE_OIDC_REDIRECT_URI)
OIDC_SCOPES=$(read_va VITE_OIDC_SCOPES)
OIDC_ORGANIZATION=$(read_va VITE_OIDC_ORGANIZATION)
GA_MEASUREMENT_ID=$(read_va VITE_GA_MEASUREMENT_ID)
LD_CLIENT_ID=$(read_va LAUNCHDARKLY_CLIENT_ID)

# ── render JSON ───────────────────────────────────────────────────────
# Field names match the React app's runtime contract verbatim. Don't
# rename anything here without coordinating with the SPA — it reads
# this file at startup, not via a typed schema.
TMP_JSON=$(mktemp)
trap 'rm -f "$TMP_JSON" "$TMP_JSON.tmp"' EXIT

jq -n \
  --arg client_id          "$CLIENT-$ENV" \
  --arg client_name        "$(echo "$CLIENT" | sed 's/^./\U&/') $ENV" \
  --arg env_name           "$ENV" \
  --arg oidc_wellknown     "$OIDC_WELLKNOWN" \
  --arg oidc_token         "$OIDC_TOKEN" \
  --arg oidc_userinfo      "$OIDC_USERINFO" \
  --arg oidc_authorize     "$OIDC_AUTHORIZE" \
  --arg oidc_idp           "$OIDC_IDP" \
  --arg oidc_client_id     "$OIDC_CLIENT_ID" \
  --arg oidc_redirect      "$OIDC_REDIRECT" \
  --arg oidc_scopes        "$OIDC_SCOPES" \
  --arg oidc_audience      "$OIDC_AUDIENCE" \
  --arg oidc_organization  "$OIDC_ORGANIZATION" \
  --arg graphql_uri        "$GRAPHQL_URI" \
  --arg graphql_ws         "$GRAPHQL_WS_URI" \
  --arg recording_uri      "$RECORDING_URI" \
  --arg help_ticket_uri    "$HELP_TICKET_URI" \
  --arg alb_hostname       "$ALB_HOSTNAME" \
  --arg ga_measurement_id  "$GA_MEASUREMENT_ID" \
  --arg ld_client_id       "$LD_CLIENT_ID" \
  --arg pulse_agent_base_uri "$PULSE_AGENT_BASE_URI" \
  '{
    CLIENT_ID:              $client_id,
    CLIENT_NAME:            $client_name,
    ENVIRONMENT_NAME:       $env_name,
    OIDC_WELLKNOWN_URL:     $oidc_wellknown,
    OIDC_TOKEN_URL:         $oidc_token,
    OIDC_USERINFO_URL:      $oidc_userinfo,
    OIDC_AUTHORIZE_URL:     $oidc_authorize,
    OIDC_IDP_CONNECTION:    $oidc_idp,
    OIDC_CLIENT_ID:         $oidc_client_id,
    OIDC_REDIRECT_URI:      $oidc_redirect,
    OIDC_SCOPES:            $oidc_scopes,
    OIDC_AUDIENCE:          $oidc_audience,
    OIDC_ORGANIZATION:      $oidc_organization,
    GRAPHQL_URI:            $graphql_uri,
    GRAPHQL_WS_URI:         $graphql_ws,
    RECORDING_URI:          $recording_uri,
    HELP_TICKET_URI:        $help_ticket_uri,
    PUBLIC_ALB_HOSTNAME:    $alb_hostname,
    LAUNCHDARKLY_CLIENT_ID: $ld_client_id,
    GA_MEASUREMENT_ID:      $ga_measurement_id,
    PULSE_AGENT_BASE_URI:   $pulse_agent_base_uri,
    BRANDING:               { logo: "", primaryColor: "", companyName: "" }
  }' > "$TMP_JSON"

# ── env-suffixed overrides ────────────────────────────────────────────
# Append derived/explicit values for PLAYGROUND, PREVIEW, PRODUCTION.
# PLAYGROUND uses derivation when no explicit value is set; the others
# remain explicit-only (no convention).
add_field() {
  local key="$1" value="$2"
  if [ -n "$value" ]; then
    jq --arg v "$value" ".${key} = \$v" "$TMP_JSON" > "$TMP_JSON.tmp"
    mv "$TMP_JSON.tmp" "$TMP_JSON"
  fi
}

add_field "GRAPHQL_URI_PLAYGROUND"             "$GRAPHQL_URI_PLAYGROUND"
add_field "GRAPHQL_WS_URI_PLAYGROUND"          "$GRAPHQL_WS_URI_PLAYGROUND"
add_field "RECORDING_DOWNLOAD_ENDPOINT_PLAYGROUND" "$RECORDING_URI_PLAYGROUND"

for ENV_SUFFIX in PREVIEW PRODUCTION; do
  add_field "GRAPHQL_URI_${ENV_SUFFIX}"             "$(read_va "VITE_GRAPHQL_URI_${ENV_SUFFIX}")"
  add_field "GRAPHQL_WS_URI_${ENV_SUFFIX}"          "$(read_va "VITE_GRAPHQL_WS_URI_${ENV_SUFFIX}")"
  add_field "RECORDING_DOWNLOAD_ENDPOINT_${ENV_SUFFIX}" "$(read_va "VITE_RECORDING_URI_${ENV_SUFFIX}")"
done

# ── emit ──────────────────────────────────────────────────────────────
# When OUTPUT_FILE is set, write JSON to the file and emit only the
# resolved DOMAIN / PROD_DOMAIN as KEY=VALUE lines on stdout (so the
# caller can `eval` them). When OUTPUT_FILE is unset, write JSON to
# stdout and skip the KEY=VALUE echoes so the JSON output stays
# parseable.
if [ -n "${OUTPUT_FILE:-}" ]; then
  cp "$TMP_JSON" "$OUTPUT_FILE"
  echo "📝 Generated auth config: $OUTPUT_FILE (DOMAIN=$DOMAIN, PROD_DOMAIN=$PROD_DOMAIN)" >&2
  echo "DOMAIN=$DOMAIN"
  echo "PROD_DOMAIN=$PROD_DOMAIN"
else
  cat "$TMP_JSON"
  echo "📝 Generated auth config to stdout (DOMAIN=$DOMAIN, PROD_DOMAIN=$PROD_DOMAIN)" >&2
fi
