#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_WORKTREE_ROOT="${RELEASE_WORKTREE_ROOT:-$REPO_ROOT/.release-worktrees}"
RELEASE_ARTIFACT_ROOT="${RELEASE_ARTIFACT_ROOT:-$REPO_ROOT/.release-artifacts}"
STATE_ROOT="${RELEASE_STATE_ROOT:-$REPO_ROOT/.agents/state/tasks}"
PUBLIC_DOMAIN="gptch.cloud"
CANVAS_PATH="vendor/infinite-canvas"

TASK_ID=""
DOMAIN=""
SOURCE_REF=""
PHASE=""

die() {
    printf 'release-control: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  scripts/deploy/release-control.sh prepare-worktree --task-id <id> --domain gptch.cloud --source-ref <40-char-sha>
  scripts/deploy/release-control.sh prepare-composite --task-id <id> --domain gptch.cloud
  scripts/deploy/release-control.sh dry-run --task-id <id> --phase local-preparation

This controller only prepares local source evidence. It never builds images,
contacts production, transfers archives, starts containers, or changes Nginx.
EOF
}

require_value() {
    [ -n "${2:-}" ] || die "missing value for $1"
}

parse_common_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --task-id)
                require_value "$1" "${2:-}"
                TASK_ID="$2"
                shift 2
                ;;
            --domain)
                require_value "$1" "${2:-}"
                DOMAIN="$2"
                shift 2
                ;;
            --source-ref)
                require_value "$1" "${2:-}"
                SOURCE_REF="$2"
                shift 2
                ;;
            --phase)
                require_value "$1" "${2:-}"
                PHASE="$2"
                shift 2
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done
}

validate_task() {
    [[ "$TASK_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || die "task id must contain only letters, numbers, dot, underscore, or dash"
}

validate_domain() {
    [ "$DOMAIN" = "$PUBLIC_DOMAIN" ] || die "this controller is bound to $PUBLIC_DOMAIN"
}

validate_source_ref() {
    [[ "$SOURCE_REF" =~ ^[0-9a-f]{40}$ ]] || die "source ref must be an immutable 40-character commit SHA"
}

task_state_dir() {
    printf '%s/%s' "$STATE_ROOT" "$TASK_ID"
}

task_worktree() {
    printf '%s/%s' "$RELEASE_WORKTREE_ROOT" "$TASK_ID"
}

task_artifact_dir() {
    printf '%s/%s' "$RELEASE_ARTIFACT_ROOT" "$TASK_ID"
}

manifest_path() {
    printf '%s/process.md' "$(task_state_dir)"
}

assert_attached_checkout_clean() {
    local status
    status="$(git -C "$REPO_ROOT" status --porcelain)"
    [ -z "$status" ] || die "attached checkout is dirty; commit or remove local changes before release preparation"
}

assert_pushed_main_commit() {
    local source_sha remote_sha
    source_sha="$(git -C "$REPO_ROOT" rev-parse --verify "$SOURCE_REF^{commit}")"
    [ "$source_sha" = "$SOURCE_REF" ] || die "source ref does not resolve to the requested immutable SHA"
    remote_sha="$(git -C "$REPO_ROOT" ls-remote origin refs/heads/main | awk 'NR == 1 { print $1 }')"
    [ -n "$remote_sha" ] || die "could not resolve origin/main"
    git -C "$REPO_ROOT" merge-base --is-ancestor "$source_sha" "$remote_sha" || die "source commit is not contained in origin/main"
}

canvas_gitlink_sha() {
    local parent_sha="$1" entry
    entry="$(git -C "$REPO_ROOT" ls-tree "$parent_sha" "$CANVAS_PATH")"
    [[ "$entry" =~ ^160000[[:space:]]commit[[:space:]]([0-9a-f]{40}) ]] || die "missing Canvas gitlink at $CANVAS_PATH"
    printf '%s' "${BASH_REMATCH[1]}"
}

assert_canvas_openai_base() {
    local canvas_dir="$1" matches count
    matches="$(grep -R --include='*.ts' --include='*.tsx' --exclude-dir=.git -nE '^[[:space:]]*const OPENAI_BASE_URL = "https://gptch\.cloud";[[:space:]]*$' "$canvas_dir" || true)"
    count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
    [ "$count" = "1" ] || die "Canvas source must contain exactly one static OPENAI_BASE_URL = https://gptch.cloud"
}

assert_prepared_pair() {
    local worktree="$1" parent_sha="$2" canvas_sha
    [ -d "$worktree/.git" ] || [ -f "$worktree/.git" ] || die "prepared worktree is missing: $worktree"
    [ "$(git -C "$worktree" rev-parse HEAD)" = "$parent_sha" ] || die "prepared worktree parent commit does not match manifest"
    canvas_sha="$(canvas_gitlink_sha "$parent_sha")"
    [ -d "$worktree/$CANVAS_PATH/.git" ] || [ -f "$worktree/$CANVAS_PATH/.git" ] || die "Canvas submodule is not initialized"
    [ "$(git -C "$worktree/$CANVAS_PATH" rev-parse HEAD)" = "$canvas_sha" ] || die "Canvas checkout does not match parent gitlink"
    [ -z "$(git -C "$worktree" status --porcelain --ignore-submodules=none)" ] || die "prepared worktree is dirty"
    [ -z "$(git -C "$worktree/$CANVAS_PATH" status --porcelain)" ] || die "Canvas checkout is dirty"
    assert_canvas_openai_base "$worktree/$CANVAS_PATH"
}

read_manifest_value() {
    local label="$1"
    sed -n "s/^- ${label}: //p" "$(manifest_path)" | head -n 1
}

write_manifest() {
    local parent_sha="$1" canvas_sha="$2" worktree="$3" artifact_dir="$4" archive="$artifact_dir/source-composite.tar"
    local archive_sha="pending" shell_dockerfile_sha canvas_dockerfile_sha
    shell_dockerfile_sha="$(shasum -a 256 "$worktree/Dockerfile" | awk '{print $1}')"
    canvas_dockerfile_sha="$(shasum -a 256 "$worktree/$CANVAS_PATH/Dockerfile" | awk '{print $1}')"
    [ -f "$archive" ] && archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
    mkdir -p "$(task_state_dir)"
    cat >"$(manifest_path)" <<EOF
# gptch.cloud Image Release Manifest

## Source
- Domain: $PUBLIC_DOMAIN
- Parent Commit: $parent_sha
- Canvas Gitlink Commit: $canvas_sha
- Canvas OPENAI_BASE_URL: https://gptch.cloud
- Worktree: $worktree
- Shell Dockerfile SHA-256: $shell_dockerfile_sha
- Canvas Dockerfile SHA-256: $canvas_dockerfile_sha

## Composite Archive
- Path: $archive
- SHA-256: $archive_sha

## Profile
- Status: unverified; fresh read-only discovery must report ready-for-bluegreen before any remote phase.
- Allowed Routes: /image/, /canvas/, /canvas-uploads/

## Artifacts
- Shell Image: pending
- Canvas Image: pending
- Uploads Edge Image: unchanged unless explicitly included in the release plan

## Production
- Candidate Topology: pending discovery
- Rollback: no production action has been authorized or performed
EOF
}

prepare_worktree() {
    validate_task
    validate_domain
    validate_source_ref
    assert_attached_checkout_clean
    assert_pushed_main_commit

    local parent_sha canvas_sha worktree artifact_dir
    parent_sha="$(git -C "$REPO_ROOT" rev-parse "$SOURCE_REF")"
    canvas_sha="$(canvas_gitlink_sha "$parent_sha")"
    worktree="$(task_worktree)"
    artifact_dir="$(task_artifact_dir)"
    mkdir -p "$RELEASE_WORKTREE_ROOT" "$artifact_dir"

    if [ -e "$worktree" ]; then
        assert_prepared_pair "$worktree" "$parent_sha"
    else
        git -C "$REPO_ROOT" worktree add --detach "$worktree" "$parent_sha"
        git -C "$worktree" submodule update --init --recursive "$CANVAS_PATH"
        assert_prepared_pair "$worktree" "$parent_sha"
    fi

    write_manifest "$parent_sha" "$canvas_sha" "$worktree" "$artifact_dir"
    printf 'prepared_worktree=%s\nparent_commit=%s\ncanvas_commit=%s\nmanifest=%s\n' "$worktree" "$parent_sha" "$canvas_sha" "$(manifest_path)"
}

prepare_composite() {
    validate_task
    validate_domain
    local parent_sha canvas_sha worktree artifact_dir context archive
    [ -f "$(manifest_path)" ] || die "run prepare-worktree first"
    parent_sha="$(read_manifest_value 'Parent Commit')"
    canvas_sha="$(read_manifest_value 'Canvas Gitlink Commit')"
    worktree="$(read_manifest_value 'Worktree')"
    [ -n "$parent_sha" ] && [ -n "$canvas_sha" ] && [ -n "$worktree" ] || die "release manifest is incomplete"
    assert_prepared_pair "$worktree" "$parent_sha"
    [ "$(canvas_gitlink_sha "$parent_sha")" = "$canvas_sha" ] || die "manifest Canvas commit does not match parent gitlink"

    artifact_dir="$(task_artifact_dir)"
    context="$artifact_dir/source-composite"
    archive="$artifact_dir/source-composite.tar"
    rm -rf "$context" "$archive"
    mkdir -p "$context/$CANVAS_PATH"
    git -C "$worktree" archive "$parent_sha" | tar -xf - -C "$context"
    git -C "$worktree/$CANVAS_PATH" archive "$canvas_sha" | tar -xf - -C "$context/$CANVAS_PATH"
    tar -cf "$archive" -C "$context" .
    write_manifest "$parent_sha" "$canvas_sha" "$worktree" "$artifact_dir"
    printf 'composite_archive=%s\nsha256=%s\n' "$archive" "$(shasum -a 256 "$archive" | awk '{print $1}')"
}

dry_run() {
    validate_task
    [ "$PHASE" = "local-preparation" ] || die "only --phase local-preparation is permitted; remote release phases require a ready profile and separate production authorization"
    [ -f "$(manifest_path)" ] || die "run prepare-worktree first"
    local parent_sha worktree
    parent_sha="$(read_manifest_value 'Parent Commit')"
    worktree="$(read_manifest_value 'Worktree')"
    [ -n "$parent_sha" ] && [ -n "$worktree" ] || die "release manifest is incomplete"
    assert_prepared_pair "$worktree" "$parent_sha"
    printf 'dry_run=local-preparation\ntask_id=%s\nparent_commit=%s\ncanvas_commit=%s\nstatus=ready-for-build-host-preflight\n' "$TASK_ID" "$parent_sha" "$(canvas_gitlink_sha "$parent_sha")"
}

main() {
    local command="${1:-}"
    [ -n "$command" ] || {
        usage
        exit 1
    }
    shift
    case "$command" in
        prepare-worktree)
            parse_common_args "$@"
            prepare_worktree
            ;;
        prepare-composite)
            parse_common_args "$@"
            prepare_composite
            ;;
        dry-run)
            parse_common_args "$@"
            dry_run
            ;;
        -h|--help)
            usage
            ;;
        *)
            die "unknown command: $command"
            ;;
    esac
}

main "$@"
