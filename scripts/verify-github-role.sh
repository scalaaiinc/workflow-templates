#!/bin/bash
# Verify GitHub OIDC Role permissions for CodeArtifact
# This script checks if the GitHub role can authenticate and publish to CodeArtifact

set -e

ROLE_ARN="arn:aws:iam::579107446826:role/cdk-hnb659fds-github-role-579107446826-us-east-1"
DOMAIN="scala"
REPOSITORY="python-packages"
REGION="us-east-1"

echo "🔍 Verifying GitHub OIDC Role for CodeArtifact Access"
echo "=================================================="
echo ""

# Check if the role exists
echo "1️⃣ Checking if role exists..."
if aws iam get-role --role-name cdk-hnb659fds-github-role-579107446826-us-east-1 --region us-east-1 2>/dev/null; then
    echo "✅ Role exists: $ROLE_ARN"
else
    echo "❌ Role not found: $ROLE_ARN"
    exit 1
fi

echo ""

# Check role's trust policy
echo "2️⃣ Checking OIDC trust policy..."
TRUST_POLICY=$(aws iam get-role --role-name cdk-hnb659fds-github-role-579107446826-us-east-1 --region us-east-1 --query 'Role.AssumeRolePolicyDocument' --output json)
if echo "$TRUST_POLICY" | grep -q "token.actions.githubusercontent.com"; then
    echo "✅ OIDC trust policy configured for GitHub Actions"
    echo "$TRUST_POLICY" | jq '.Statement[0].Condition'
else
    echo "❌ OIDC trust policy not found"
    exit 1
fi

echo ""

# Check attached policies
echo "3️⃣ Checking attached managed policies..."
MANAGED_POLICIES=$(aws iam list-attached-role-policies --role-name cdk-hnb659fds-github-role-579107446826-us-east-1 --region us-east-1 --query 'AttachedPolicies[*].PolicyName' --output text)
echo "Managed policies: $MANAGED_POLICIES"

if echo "$MANAGED_POLICIES" | grep -q "PowerUserAccess"; then
    echo "✅ PowerUserAccess policy attached"
else
    echo "⚠️  PowerUserAccess policy not attached"
fi

echo ""

# Check inline policies for CodeArtifact permissions
echo "4️⃣ Checking inline policies for CodeArtifact permissions..."
POLICY_NAMES=$(aws iam list-role-policies --role-name cdk-hnb659fds-github-role-579107446826-us-east-1 --region us-east-1 --query 'PolicyNames' --output text)
if [ -n "$POLICY_NAMES" ]; then
    echo "Inline policies found: $POLICY_NAMES"
    for policy in $POLICY_NAMES; do
        echo ""
        echo "Policy: $policy"
        POLICY_DOC=$(aws iam get-role-policy --role-name cdk-hnb659fds-github-role-579107446826-us-east-1 --policy-name "$policy" --region us-east-1 --query 'PolicyDocument' --output json)
        
        # Check for CodeArtifact permissions
        if echo "$POLICY_DOC" | grep -q "codeartifact"; then
            echo "✅ CodeArtifact permissions found"
            echo "$POLICY_DOC" | jq '.Statement[] | select(.Sid == "CodeArtifact")'
        fi
        
        # Check for STS CodeArtifact token permissions
        if echo "$POLICY_DOC" | grep -q "GetServiceBearerToken"; then
            echo "✅ STS GetServiceBearerToken permission found"
            echo "$POLICY_DOC" | jq '.Statement[] | select(.Sid == "STSCodeArtifact")'
        fi
    done
else
    echo "No inline policies found"
fi

echo ""

# Check if CodeArtifact domain and repository exist
echo "5️⃣ Checking CodeArtifact domain and repository..."
if aws codeartifact describe-domain --domain $DOMAIN --domain-owner 579107446826 --region $REGION >/dev/null 2>&1; then
    echo "✅ Domain exists: $DOMAIN"
else
    echo "❌ Domain not found: $DOMAIN"
    exit 1
fi

if aws codeartifact describe-repository --domain $DOMAIN --domain-owner 579107446826 --repository $REPOSITORY --region $REGION >/dev/null 2>&1; then
    echo "✅ Repository exists: $REPOSITORY"
else
    echo "❌ Repository not found: $REPOSITORY"
    exit 1
fi

echo ""
echo "=================================================="
echo "✅ All checks passed!"
echo ""
echo "📋 Summary:"
echo "   Role: $ROLE_ARN"
echo "   Domain: $DOMAIN"
echo "   Repository: $REPOSITORY"
echo "   Region: $REGION"
echo ""
echo "🔐 Required workflow permissions:"
echo "   permissions:"
echo "     id-token: write"
echo "     contents: read"
echo ""
echo "📝 Workflow configuration:"
echo "   - name: Configure AWS Credentials"
echo "     uses: aws-actions/configure-aws-credentials@v4"
echo "     with:"
echo "       role-to-assume: $ROLE_ARN"
echo "       aws-region: $REGION"
