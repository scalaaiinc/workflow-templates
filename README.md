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

# CI/CD pipeline for Node Module
TBD
