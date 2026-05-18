#!/usr/bin/env bash
# scripts/test/run-tests.sh
#
# End-to-end fixture tests for generate-spa-auth-config.sh.
#
# Each test loads a fixture cdk.context.json, runs the generator,
# and asserts that specific output JSON keys have the expected
# values. Failures print a diff of the full generated JSON so the
# offending field is easy to spot.
#
# Why bash rather than e.g. Bats? The script under test is a thin
# bash wrapper around jq, and adding a Bats dep would be the only
# Python/Node touchpoint in this repo. A few hand-rolled assertions
# beat dragging in a framework.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../lib/generate-spa-auth-config.sh"
FIXTURES="$HERE/fixtures"

if [ ! -x "$SCRIPT" ]; then
  echo "::error::generator script not executable at $SCRIPT" >&2
  exit 2
fi

PASS=0
FAIL=0

# fail_test prints a contextual error and bumps the FAIL counter,
# then returns 1 so the caller can decide whether to short-circuit.
fail_test() {
  echo "  ❌ $1" >&2
  FAIL=$((FAIL + 1))
  return 1
}

# assert_eq KEY EXPECTED JSON_FILE
# Asserts that the JSON value at .KEY equals EXPECTED.
assert_eq() {
  local key="$1" expected="$2" file="$3"
  local actual
  actual=$(jq -r ".${key}" "$file")
  if [ "$actual" = "$expected" ]; then
    echo "  ✓ $key = $expected"
  else
    fail_test "$key: expected '$expected' but got '$actual'" || true
  fi
}

# run_test NAME FIXTURE CDK_ENV CLIENT ENV   — invokes the script
# with the fixture and stashes the JSON in $OUT for the caller to
# inspect via assert_eq.
run_test() {
  local name="$1" fixture="$2" cdk_env="$3" client="$4" env="$5"
  echo "▶ $name"
  OUT=$(mktemp)
  CONTEXT_FILE="$FIXTURES/$fixture" CDK_ENV="$cdk_env" CLIENT="$client" ENV="$env" \
    OUTPUT_FILE="$OUT" "$SCRIPT" >/dev/null
  PASS=$((PASS + 1))
}

# ── Test 1: explicit values pass through unchanged ────────────────────
# Backwards-compat guarantee: a config that lists every VITE_* field
# explicitly must produce the same output as before VOYAG-409.
run_test "lyric-prod with all values explicit" lyric-prod-explicit.json lyric-prod lyric prod
assert_eq GRAPHQL_URI            "https://lyric.scala.ai/graphql"            "$OUT"
assert_eq GRAPHQL_WS_URI         "wss://lyric.scala.ai/graphql"              "$OUT"
assert_eq OIDC_AUDIENCE          "https://lyric.scala.ai/api"                "$OUT"
assert_eq HELP_TICKET_URI        "https://lyric.scala.ai/ticket"             "$OUT"
assert_eq PUBLIC_ALB_HOSTNAME    "services.lyric.scala.ai"                   "$OUT"
assert_eq RECORDING_URI          "https://lyric.scala.ai/recordings/download" "$OUT"
assert_eq GRAPHQL_URI_PLAYGROUND "https://playground.lyric.scala.ai/graphql" "$OUT"
assert_eq GRAPHQL_WS_URI_PLAYGROUND "wss://playground.lyric.scala.ai/graphql" "$OUT"
assert_eq RECORDING_DOWNLOAD_ENDPOINT_PLAYGROUND "https://playground.lyric.scala.ai/recordings/download" "$OUT"
assert_eq OIDC_CLIENT_ID         "89tllloKa2kmlFSwhXxWGM7dHVaWp6gp"          "$OUT"
assert_eq LAUNCHDARKLY_CLIENT_ID "69c59e5bcf0b5d0b823ebbf9"                  "$OUT"

# ── Test 2: derived values match the explicit ones byte-for-byte ──────
# This is the core promise of VOYAG-409. With every URL stripped from
# config, the output must be identical to Test 1's output for the
# derivable fields.
run_test "lyric-prod with all derivable fields stripped" lyric-prod-derived.json lyric-prod lyric prod
assert_eq GRAPHQL_URI            "https://lyric.scala.ai/graphql"            "$OUT"
assert_eq GRAPHQL_WS_URI         "wss://lyric.scala.ai/graphql"              "$OUT"
assert_eq OIDC_AUDIENCE          "https://lyric.scala.ai/api"                "$OUT"
assert_eq HELP_TICKET_URI        "https://lyric.scala.ai/ticket"             "$OUT"
assert_eq PUBLIC_ALB_HOSTNAME    "services.lyric.scala.ai"                   "$OUT"
assert_eq RECORDING_URI          "https://lyric.scala.ai/recordings/download" "$OUT"
assert_eq GRAPHQL_URI_PLAYGROUND "https://playground.lyric.scala.ai/graphql" "$OUT"
assert_eq GRAPHQL_WS_URI_PLAYGROUND "wss://playground.lyric.scala.ai/graphql" "$OUT"
assert_eq RECORDING_DOWNLOAD_ENDPOINT_PLAYGROUND "https://playground.lyric.scala.ai/recordings/download" "$OUT"
# Pure passthroughs still flow through untouched.
assert_eq OIDC_CLIENT_ID         "89tllloKa2kmlFSwhXxWGM7dHVaWp6gp"          "$OUT"

# ── Test 3: per-field override still wins over derivation ─────────────
# A partial override (only GRAPHQL_URI and PUBLIC_ALB_HOSTNAME set)
# must keep those as-is and derive the rest.
run_test "lyric-prod with mixed explicit + derived" lyric-prod-mixed.json lyric-prod lyric prod
assert_eq GRAPHQL_URI            "https://overridden.example.com/gql"        "$OUT"
assert_eq PUBLIC_ALB_HOSTNAME    "alb.weird.example.com"                     "$OUT"
# These weren't overridden — must be derived.
assert_eq GRAPHQL_WS_URI         "wss://lyric.scala.ai/graphql"              "$OUT"
assert_eq OIDC_AUDIENCE          "https://lyric.scala.ai/api"                "$OUT"
assert_eq HELP_TICKET_URI        "https://lyric.scala.ai/ticket"             "$OUT"

# ── Test 4: PROD_DOMAIN override decouples from dns_config.domain ─────
# A preview env serving from preview.lyric.scala.ai (its own DOMAIN)
# can still point at lyric.scala.ai's APIs by setting PROD_DOMAIN.
# This is the escape hatch for envs that have their own CloudFront
# but talk back to prod's services.
run_test "lyric-preview overrides PROD_DOMAIN to point at prod" lyric-preview-prod-domain.json lyric-preview lyric preview
assert_eq GRAPHQL_URI         "https://lyric.scala.ai/graphql" "$OUT"
assert_eq GRAPHQL_WS_URI      "wss://lyric.scala.ai/graphql"   "$OUT"
assert_eq OIDC_AUDIENCE       "https://lyric.scala.ai/api"     "$OUT"
assert_eq HELP_TICKET_URI     "https://lyric.scala.ai/ticket"  "$OUT"
assert_eq PUBLIC_ALB_HOSTNAME "services.lyric.scala.ai"        "$OUT"

# ── Test 5: shape matches the React app contract ──────────────────────
# Catch accidental key renames/removals. The list below is the SPA's
# read contract and must NOT change without coordination with
# react-voyager-app.
run_test "output shape contains expected top-level keys" lyric-prod-derived.json lyric-prod lyric prod
EXPECTED_KEYS=(
  CLIENT_ID CLIENT_NAME ENVIRONMENT_NAME
  OIDC_WELLKNOWN_URL OIDC_TOKEN_URL OIDC_USERINFO_URL OIDC_AUTHORIZE_URL
  OIDC_IDP_CONNECTION OIDC_CLIENT_ID OIDC_REDIRECT_URI OIDC_SCOPES
  OIDC_AUDIENCE OIDC_ORGANIZATION
  GRAPHQL_URI GRAPHQL_WS_URI RECORDING_URI HELP_TICKET_URI PUBLIC_ALB_HOSTNAME
  LAUNCHDARKLY_CLIENT_ID GA_MEASUREMENT_ID BRANDING
)
for k in "${EXPECTED_KEYS[@]}"; do
  if ! jq -e "has(\"$k\")" "$OUT" >/dev/null; then
    fail_test "missing top-level key: $k" || true
  else
    echo "  ✓ has key: $k"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "❌ $FAIL assertion(s) failed across $PASS test case(s)" >&2
  exit 1
fi
echo "✅ all $PASS test cases passed"
