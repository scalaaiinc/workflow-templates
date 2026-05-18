# `generate-spa-config` action

Builds the runtime SPA auth-config JSON (`{domain}.json`) for the
voyager-app from a merged `cdk.context.json` and uploads it to the
target account's auth-config S3 bucket.

```
.github/actions/generate-spa-config/
├── action.yml                       # composite action entrypoint
├── lib/
│   └── generate-spa-auth-config.sh  # the actual generator (testable)
├── test/
│   ├── run-tests.sh                 # bash test runner
│   └── fixtures/                    # sample cdk.context.json inputs
└── README.md
```

The action is fully self-contained: every file it needs lives under
this directory. It can be referenced cross-repo as

```yaml
uses: scalaaiinc/workflow-templates/.github/actions/generate-spa-config@main
```

…and GitHub will check out only this repo to make the sibling
`lib/` files available.

## PROD_DOMAIN convention (VOYAG-409)

Most `VITE_*` URL fields are derived from a single `PROD_DOMAIN` so
the per-env config can stay tiny and drift-free. Explicit values in
`voyager-app.*` always win over derivation, so existing client
configs continue to work unchanged.

| Field | Derived value (when not explicitly set) |
| --- | --- |
| `VITE_GRAPHQL_URI` | `https://{PROD_DOMAIN}/graphql` |
| `VITE_GRAPHQL_URI_PLAYGROUND` | `https://playground.{PROD_DOMAIN}/graphql` |
| `VITE_GRAPHQL_WS_URI` | `wss://{PROD_DOMAIN}/graphql` |
| `VITE_GRAPHQL_WS_URI_PLAYGROUND` | `wss://playground.{PROD_DOMAIN}/graphql` |
| `VITE_OIDC_AUDIENCE` | `https://{PROD_DOMAIN}/api` |
| `VITE_HELP_TICKET_URI` | `https://{PROD_DOMAIN}/ticket` |
| `VITE_PUBLIC_ALB_HOSTNAME` | `services.{PROD_DOMAIN}` |
| `VITE_RECORDING_URI` | `https://{PROD_DOMAIN}/recordings/download` |
| `VITE_RECORDING_URI_PLAYGROUND` | `https://playground.{PROD_DOMAIN}/recordings/download` |

`PROD_DOMAIN` itself defaults to `core-infra.dns_config.domain`. A
client may override it via `voyager-app.PROD_DOMAIN` for envs that
serve from their own CloudFront but should still hit prod URLs (rare).

Per-tenant secrets / IDs (`VITE_OIDC_CLIENT_ID`, `VITE_OIDC_REDIRECT_URI`,
`VITE_GA_MEASUREMENT_ID`, `LAUNCHDARKLY_CLIENT_ID`, `VITE_OIDC_ORGANIZATION`,
…) stay explicit-only — there's no convention to derive them from.

## Running the script standalone

```bash
CONTEXT_FILE=path/to/cdk.context.json \
CDK_ENV=lyric-prod \
CLIENT=lyric \
ENV=prod \
OUTPUT_FILE=/tmp/auth-config.json \
  bash .github/actions/generate-spa-config/lib/generate-spa-auth-config.sh
```

When `OUTPUT_FILE` is set, JSON is written to the file and the script
emits `DOMAIN=…` / `PROD_DOMAIN=…` lines on stdout (suitable for
`eval`). When unset, JSON is written to stdout.

## Tests

```bash
bash .github/actions/generate-spa-config/test/run-tests.sh
```

Add a fixture under `test/fixtures/` and corresponding assertions in
`test/run-tests.sh` whenever you introduce a new derivation rule or
pass-through field.
