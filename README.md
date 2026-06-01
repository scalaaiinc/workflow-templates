# GitHub shared workflows

To leverage shared workflows, create a new YAML file in your repository's `.github/workflows` directory. For the main CI/CD pipeline, it's a good practice to name the YAML file `main.yml` (`.github/workflows/main.yml`)

## CI/CD rules for Services and AWS Lambdas
* Push to any branch runs UNIT tests
* Push to feature (`feature/feature-name`) runs UNIT tests, and if successful, it pushes the Service and/or AWS Lambda to the `playground` environment.
* Push to `main` branch runs UNIT tests, and if successful, it pushes the Service and/or AWS Lambda to the `preview` environment.
* Creating a release runs UNIT tests, and if successful, it pushes the Service and/or AWS Lambda to the `live` environment.

## CI/CD rules for modules
* Push to any branch runs UNIT tests
* Creating a release runs UNIT tests, and if successful, it builds the artifact and uploads it to the AWS CodeArtifact.

# YAML template
```yaml
name: CI/CD Pipeline

on:
  push:
    branches:
      - main
      - develop
      - 'feature/**'
  pull_request:
    branches:
      - main
      - develop
  release:
    types: [created]

jobs:
  build-test-deploy:
    uses: <replace with shared workflows from below>
    secrets: inherit
``` 

# CI/CD pipeline for Python Module
`scalaaiinc/workflow-templates/.github/workflows/python-module.yml@main`

# CI/CD pipeline for Fargate Service
`scalaaiinc/workflow-templates/.github/workflows/python-aws-cdk.yml@main`

# CI/CD pipeline for AWS Lambda
TBD

# CI/CD pipeline for Flutter Fargate Service
`scalaaiinc/workflow-templates/.github/workflows/flutter-aws-cdk.yml@main`

# CI/CD pipeline for Node Module
TBD

# JIRA notification on Release published
`scalaaiinc/workflow-templates/.github/workflows/jira-release-published.yml@main`

When a GitHub Release is published, this workflow gathers every JIRA issue
key (default pattern: `VOYAG-N`) referenced anywhere in the release range —
the release name, release body, and every commit reachable from the new tag
but not from the previously published release — then POSTs the combined
unique list to a JIRA Automation incoming webhook so a single rule can fan
out per-issue actions (label with `shipped-in:<tag>`, transition to
"Released", comment with the release URL, etc.).

> **For per-PR JIRA linking on merge**, do *not* use this workflow. The
> [GitHub for Jira](https://github.com/marketplace/jira-software-github) app
> already emits a native **"Pull request merged"** trigger in JIRA Automation
> with the linked issues bound to `{{issue}}` — you don't need any GHA for
> that case. This workflow is specifically for *release-shipped* automation
> ("which tickets shipped in v1.2.3?").

## Setup

1. In JIRA, create an Automation rule with trigger **Incoming webhook** and
   choose **Issues provided in webhook data** (or set the request to
   `?issues=KEY-1,KEY-2` — this workflow sends both). The payload body also
   carries `data.release.{tag,previous_tag,name,url,...}` for use in
   downstream actions.
2. Copy the webhook URL and store it as a repo or org secret named
   `JIRA_WEBHOOK_URL`.
3. Add a workflow in your repo at `.github/workflows/jira-release-published.yml`:

```yaml
name: JIRA Release Published

on:
  release:
    types: [published]

jobs:
  notify-jira:
    uses: scalaaiinc/workflow-templates/.github/workflows/jira-release-published.yml@main
    secrets: inherit
    # Optional overrides:
    # with:
    #   jira_key_pattern: 'VOYAG-[0-9]+'   # default
    #   release_branch: main                # default; only main releases notify
    #   include_prereleases: false          # default; skip prereleases
    #   fail_if_no_keys: false              # default
```

### Behavior

- **Branch gate.** The workflow only notifies for releases cut from
  `release_branch` (default `main`). It first checks
  `release.target_commitish == release_branch` (covers releases created from
  the branch via UI/CLI/API), then falls back to a `git merge-base
  --is-ancestor` check so releases pinned to a SHA on `main` still count.
  Off-branch releases (e.g. cut from a release branch or a feature branch)
  produce a clean no-op run with a note in the step summary.
- **Range.** The workflow finds the previously published release via the
  GitHub API (sorted by `published_at`, drafts excluded, prereleases excluded
  unless `include_prereleases: true`), then walks `git log <prev>..<current>`
  to gather commit messages. If there is no prior release, it scans the
  full history reachable from the current tag.
- **Sources scanned.** Release name, release body, and every commit message
  in the range. The step summary shows a per-source breakdown with the
  commit count so you can verify what got picked up.
- **Prereleases.** By default, prereleases (`prerelease: true`) are skipped
  entirely — both as triggers and as "previous release" anchors — so the
  diff always covers stable→stable. Set `include_prereleases: true` to
  notify on every release.
