#!/usr/bin/env bash
set -euo pipefail

# Provisions the GitHub repo for the npm-package project.
# Applies repo settings, branch rulesets, and tag rulesets that the GitHub UI
# would otherwise hold out-of-band.
# Safe to run multiple times — existing rulesets are updated in place.
#
# Usage:
#   scripts/provision-repo.sh                  # auto-detects repo from git remote
#   scripts/provision-repo.sh owner/repo       # explicit repo

REPO="${1:-}"

if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
    echo "Error: could not detect repo. Pass owner/repo as argument." >&2
    exit 1
  }
fi

echo "Provisioning $REPO ..."

# ── Helpers ────────────────────────────────────────────────────────────────────

# Finds an existing ruleset ID by name, or prints empty string.
ruleset_id_by_name() {
  gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$1\") | .id" 2>/dev/null || true
}

# Creates or updates a ruleset. Usage: upsert_ruleset "Name" <<'JSON' ... JSON
upsert_ruleset() {
  local name="$1"
  local body
  body=$(cat)

  local existing_id
  existing_id=$(ruleset_id_by_name "$name")

  if [[ -n "$existing_id" ]]; then
    echo "  Updating ruleset: $name (id $existing_id) ..."
    echo "$body" | gh api "repos/$REPO/rulesets/$existing_id" -X PUT --silent --input -
  else
    echo "  Creating ruleset: $name ..."
    echo "$body" | gh api "repos/$REPO/rulesets" -X POST --silent --input -
  fi
}

# ── Repo settings ──────────────────────────────────────────────────────────────
echo "  Setting merge strategy (merge-only), auto-merge, and head branch cleanup ..."
gh api "repos/$REPO" -X PATCH --silent \
  -f allow_merge_commit=true \
  -f allow_squash_merge=false \
  -f allow_rebase_merge=false \
  -f allow_auto_merge=true \
  -F delete_branch_on_merge=true \
  -F allow_update_branch=true \
  -f merge_commit_title=PR_TITLE \
  -f merge_commit_message=PR_BODY

# ── Human review gate environment ──────────────────────────────────────────────
# Solo-dev workaround: GitHub blocks PR self-approval, but allows self-approval
# on environment deployments. The "Human review gate" workflow targets this
# environment; the ruleset's required_deployments rule blocks merge (including
# auto-merge) until the approver clicks Approve on the deployment.
echo "  Configuring pr-review-gate environment (reviewer = current user) ..."
GATE_REVIEWER_ID=$(gh api user --jq '.id')
gh api "repos/$REPO/environments/pr-review-gate" -X PUT --silent --input - <<JSON
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [
    { "type": "User", "id": $GATE_REVIEWER_ID }
  ],
  "deployment_branch_policy": null
}
JSON

# ── Branch ruleset: Protect main ───────────────────────────────────────────────
# Required status checks differ from the typescript-project template: npm-package's
# PR CI runs a single `check` job (see .github/workflows/ci.yml).
upsert_ruleset "Protect main" <<'JSON'
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "pull_request"
    }
  ],
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "allowed_merge_methods": ["merge"],
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_approving_review_count": 0,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "copilot_code_review",
      "parameters": {
        "review_on_push": true,
        "review_draft_pull_requests": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "do_not_enforce_on_create": false,
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "check" }
        ]
      }
    },
    {
      "type": "required_deployments",
      "parameters": {
        "required_deployment_environments": ["pr-review-gate"]
      }
    },
    {
      "type": "deletion"
    }
  ]
}
JSON

# ── Tag ruleset: Immutable tags ────────────────────────────────────────────────
upsert_ruleset "Immutable tags" <<'JSON'
{
  "name": "Immutable tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/tags/v*"],
      "exclude": []
    }
  },
  "bypass_actors": [],
  "rules": [
    { "type": "update" },
    { "type": "deletion" }
  ]
}
JSON

# ── Release immutability ──────────────────────────────────────────────────────
echo "  Enabling release immutability ..."
gh api "repos/$REPO/immutable-releases" -X PUT --silent

# ── Security settings ──────────────────────────────────────────────────────────
echo "  Enabling secret scanning and push protection ..."
gh api "repos/$REPO" -X PATCH --silent \
  -f security_and_analysis[secret_scanning][status]=enabled \
  -f security_and_analysis[secret_scanning_push_protection][status]=enabled

echo "Done. Rulesets and security settings applied to $REPO."
