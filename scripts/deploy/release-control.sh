#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_WORKTREE_ROOT="${RELEASE_WORKTREE_ROOT:-$REPO_ROOT/.release-worktrees}"
RELEASE_ARTIFACT_ROOT="${RELEASE_ARTIFACT_ROOT:-$REPO_ROOT/.release-artifacts}"
STATE_ROOT="${RELEASE_STATE_ROOT:-$REPO_ROOT/.agents/state/tasks}"
CANVAS_PATH="vendor/infinite-canvas"

TASK_ID=""
DOMAIN=""
SOURCE_REF=""
PHASE=""
TASK_PREFIX=""
MATRIX_DOMAINS=""

die() {
    printf 'release-control: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  scripts/deploy/release-control.sh profile --domain <gptch.cloud|artworkers.online|aiunify.xyz>
  scripts/deploy/release-control.sh prepare-worktree --task-id <id> --domain <domain> --source-ref <40-char-sha>
  scripts/deploy/release-control.sh prepare-matrix --task-prefix <prefix> --source-ref <40-char-sha> [--domains <csv>]
  scripts/deploy/release-control.sh prepare-composite --task-id <id> --domain <domain>
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
            --repo-root)
                require_value "$1" "${2:-}"
                REPO_ROOT="$2"
                shift 2
                ;;
            --state-root)
                require_value "$1" "${2:-}"
                STATE_ROOT="$2"
                shift 2
                ;;
            --worktree-root)
                require_value "$1" "${2:-}"
                RELEASE_WORKTREE_ROOT="$2"
                shift 2
                ;;
            --artifact-root)
                require_value "$1" "${2:-}"
                RELEASE_ARTIFACT_ROOT="$2"
                shift 2
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done
}

require_repo_root() {
    REPO_ROOT="$(cd "$REPO_ROOT" 2>/dev/null && pwd -P)" || die "repository root does not exist: $REPO_ROOT"
    local actual_root
    actual_root="$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null)" || die "repository root is not a Git worktree: $REPO_ROOT"
    actual_root="$(cd "$actual_root" && pwd -P)"
    [ "$actual_root" = "$REPO_ROOT" ] || die "repository root must be the Git worktree root"
}

parse_matrix_args() {
    TASK_PREFIX=""
    SOURCE_REF=""
    MATRIX_DOMAINS="gptch.cloud,artworkers.online,aiunify.xyz"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --task-prefix)
                require_value "$1" "${2:-}"
                TASK_PREFIX="$2"
                shift 2
                ;;
            --source-ref)
                require_value "$1" "${2:-}"
                SOURCE_REF="$2"
                shift 2
                ;;
            --domains)
                require_value "$1" "${2:-}"
                MATRIX_DOMAINS="$2"
                shift 2
                ;;
            --repo-root)
                require_value "$1" "${2:-}"
                REPO_ROOT="$2"
                shift 2
                ;;
            --state-root)
                require_value "$1" "${2:-}"
                STATE_ROOT="$2"
                shift 2
                ;;
            --worktree-root)
                require_value "$1" "${2:-}"
                RELEASE_WORKTREE_ROOT="$2"
                shift 2
                ;;
            --artifact-root)
                require_value "$1" "${2:-}"
                RELEASE_ARTIFACT_ROOT="$2"
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

validate_task_prefix() {
    [[ "$TASK_PREFIX" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$ ]] || die "task prefix must contain only letters, numbers, dot, underscore, or dash"
}

validate_domain() {
    case "$DOMAIN" in
        gptch.cloud|artworkers.online|aiunify.xyz) ;;
        *) die "unsupported Image domain: $DOMAIN" ;;
    esac
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

domain_origin() {
    validate_domain
    printf 'https://%s' "$DOMAIN"
}

release_ref_name() {
    local domain="$1" task_id="$2" parent_sha="$3"
    printf 'refs/image-release/%s/%s/%s' "$domain" "$task_id" "$parent_sha"
}

ensure_release_ref() {
    local domain="$1" task_id="$2" parent_sha="$3" release_ref current
    release_ref="$(release_ref_name "$domain" "$task_id" "$parent_sha")"
    current="$(git -C "$REPO_ROOT" rev-parse --verify "$release_ref" 2>/dev/null || true)"
    if [ -n "$current" ] && [ "$current" != "$parent_sha" ]; then
        die "release ref already points to a different commit: $release_ref"
    fi
    if [ -z "$current" ]; then
        git -C "$REPO_ROOT" update-ref -m "image release $domain $task_id" "$release_ref" "$parent_sha"
    fi
    printf '%s' "$release_ref"
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

assert_shell_domain_build_contract() {
    grep -qE '^[[:space:]]*ARG VITE_BASE=' "$REPO_ROOT/Dockerfile" || die "Shell Dockerfile must declare VITE_BASE"
    grep -qE '^[[:space:]]*ARG VITE_FIXED_API_BASE_URL' "$REPO_ROOT/Dockerfile" || die "Shell Dockerfile must declare VITE_FIXED_API_BASE_URL"
    grep -qE '^[[:space:]]*ENV VITE_FIXED_API_BASE_URL=\$\{VITE_FIXED_API_BASE_URL\}' "$REPO_ROOT/Dockerfile" || die "Shell Dockerfile must export VITE_FIXED_API_BASE_URL"
}

canvas_gitlink_sha() {
    local parent_sha="$1" entry
    entry="$(git -C "$REPO_ROOT" ls-tree "$parent_sha" "$CANVAS_PATH")"
    [[ "$entry" =~ ^160000[[:space:]]commit[[:space:]]([0-9a-f]{40}) ]] || die "missing Canvas gitlink at $CANVAS_PATH"
    printf '%s' "${BASH_REMATCH[1]}"
}

assert_canvas_openai_base() {
    local canvas_dir="$1"
    grep -qF 'export const FIXED_API_BASE_URL = (import.meta.env.VITE_FIXED_API_BASE_URL || "").trim().replace(/\/+$/, "");' "$canvas_dir/web/src/constant/env.ts" || die "Canvas source must expose VITE_FIXED_API_BASE_URL"
    grep -qF 'const OPENAI_BASE_URL = FIXED_API_BASE_URL;' "$canvas_dir/web/src/stores/use-config-store.ts" || die "Canvas source must derive OPENAI_BASE_URL from VITE_FIXED_API_BASE_URL"
    grep -qE '^[[:space:]]*ARG VITE_FIXED_API_BASE_URL=' "$canvas_dir/Dockerfile" || die "Canvas Dockerfile must declare VITE_FIXED_API_BASE_URL"
    grep -qE '^[[:space:]]*ENV VITE_FIXED_API_BASE_URL=\$\{VITE_FIXED_API_BASE_URL\}' "$canvas_dir/Dockerfile" || die "Canvas Dockerfile must export VITE_FIXED_API_BASE_URL"
    ! grep -R --include='*.ts' --include='*.tsx' --exclude-dir=.git -q 'https://artworkers\.online' "$canvas_dir/web/src" || die "Canvas source must not hardcode artworkers.online"
}

assert_canvas_subpath_contract() {
    local canvas_dir="$1"
    grep -qF 'ARG VITE_BASE=/canvas/' "$canvas_dir/Dockerfile" || die "Canvas Dockerfile must default VITE_BASE to /canvas/"
    grep -qF 'base: appBase,' "$canvas_dir/web/vite.config.ts" || die "Canvas Vite config must use the normalized base"
    grep -qF 'basename: import.meta.env.BASE_URL' "$canvas_dir/web/src/router.tsx" || die "Canvas router must use the Vite base as basename"
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
    assert_canvas_subpath_contract "$worktree/$CANVAS_PATH"
}

assert_manifest_domain() {
    local manifest_domain
    manifest_domain="$(read_manifest_value 'Domain')"
    [ "$manifest_domain" = "$DOMAIN" ] || die "manifest domain does not match requested domain"
}

assert_manifest_release_ref() {
    local parent_sha release_ref
    parent_sha="$(read_manifest_value 'Parent Commit')"
    release_ref="$(read_manifest_value 'Release Ref')"
    [ "$release_ref" = "$(release_ref_name "$DOMAIN" "$TASK_ID" "$parent_sha")" ] || die "manifest release ref does not match the selected domain"
    [ "$(git -C "$REPO_ROOT" rev-parse --verify "$release_ref")" = "$parent_sha" ] || die "release ref does not point to the manifest parent commit"
}

read_manifest_value() {
    local label="$1"
    sed -n "s/^- ${label}: //p" "$(manifest_path)" | head -n 1
}

write_manifest() {
    local parent_sha="$1" canvas_sha="$2" worktree="$3" artifact_dir="$4" archive="$artifact_dir/source-composite.tar"
    local archive_sha="pending" shell_dockerfile_sha canvas_dockerfile_sha origin release_ref
    shell_dockerfile_sha="$(shasum -a 256 "$worktree/Dockerfile" | awk '{print $1}')"
    canvas_dockerfile_sha="$(shasum -a 256 "$worktree/$CANVAS_PATH/Dockerfile" | awk '{print $1}')"
    [ -f "$archive" ] && archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
    origin="$(domain_origin)"
    release_ref="$(release_ref_name "$DOMAIN" "$TASK_ID" "$parent_sha")"
    mkdir -p "$(task_state_dir)"
    cat >"$(manifest_path)" <<EOF
# $DOMAIN Image Release Manifest

## Source
- Domain: $DOMAIN
- Source Line: main
- Parent Commit: $parent_sha
- Canvas Gitlink Commit: $canvas_sha
- Release Ref: $release_ref
- Shell Build Args: VITE_BASE=/image/,VITE_FIXED_API_BASE_URL=$origin
- Canvas Build Args: VITE_BASE=/canvas/,VITE_FIXED_API_BASE_URL=$origin
- Canvas API Base URL: $origin
- Canvas API Source: build-time:VITE_FIXED_API_BASE_URL
- Worktree: $worktree
- Shell Dockerfile SHA-256: $shell_dockerfile_sha
- Canvas Dockerfile SHA-256: $canvas_dockerfile_sha

## Composite Archive
- Path: $archive
- SHA-256: $archive_sha

## Profile
- Status: unverified; fresh selected-domain discovery must report ready-for-bluegreen before any remote phase.
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
    require_repo_root
    validate_task
    validate_domain
    validate_source_ref
    assert_attached_checkout_clean
    assert_pushed_main_commit
    assert_shell_domain_build_contract

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

    ensure_release_ref "$DOMAIN" "$TASK_ID" "$parent_sha" >/dev/null
    write_manifest "$parent_sha" "$canvas_sha" "$worktree" "$artifact_dir"
    printf 'prepared_worktree=%s\nparent_commit=%s\ncanvas_commit=%s\nmanifest=%s\n' "$worktree" "$parent_sha" "$canvas_sha" "$(manifest_path)"
}

profile() {
    require_repo_root
    validate_domain
    local origin
    origin="$(domain_origin)"
    printf 'domain=%s\norigin=%s\nallowed_paths=/image/,/canvas/,/canvas-uploads/\n' "$DOMAIN" "$origin"
    printf 'shell_build_args=VITE_BASE=/image/,VITE_FIXED_API_BASE_URL=%s\n' "$origin"
    printf 'canvas_build_args=VITE_BASE=/canvas/,VITE_FIXED_API_BASE_URL=%s\n' "$origin"
    printf 'profile_status=unverified\nprofile_blockers=fresh-discovery-required\nremote_actions=none\n'
}

prepare_matrix() {
    require_repo_root
    validate_task_prefix
    validate_source_ref
    assert_attached_checkout_clean
    assert_pushed_main_commit

    local parent_sha domain task_id
    local -a domains
    IFS=',' read -r -a domains <<< "$MATRIX_DOMAINS"
    [ "${#domains[@]}" -gt 0 ] || die "domains must not be empty"
    local seen=,
    for domain in "${domains[@]}"; do
        [ -n "$domain" ] || die "domains must not contain an empty item"
        DOMAIN="$domain"
        validate_domain
        case "$seen" in
            *,"$domain",*) die "duplicate matrix domain: $domain" ;;
        esac
        seen="$seen$domain,"
    done

    parent_sha="$(git -C "$REPO_ROOT" rev-parse "$SOURCE_REF")"
    for domain in "${domains[@]}"; do
        TASK_ID="${TASK_PREFIX}-${domain//./-}"
        DOMAIN="$domain"
        SOURCE_REF="$parent_sha"
        prepare_worktree
    done
}

prepare_composite() {
    require_repo_root
    validate_task
    validate_domain
    local parent_sha canvas_sha worktree artifact_dir context archive
    [ -f "$(manifest_path)" ] || die "run prepare-worktree first"
    assert_manifest_domain
    assert_manifest_release_ref
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
    require_repo_root
    validate_task
    [ "$PHASE" = "local-preparation" ] || die "only --phase local-preparation is permitted; remote release phases require a ready profile and separate production authorization"
    [ -f "$(manifest_path)" ] || die "run prepare-worktree first"
    local parent_sha worktree manifest_domain
    parent_sha="$(read_manifest_value 'Parent Commit')"
    worktree="$(read_manifest_value 'Worktree')"
    manifest_domain="$(read_manifest_value 'Domain')"
    [ -n "$parent_sha" ] && [ -n "$worktree" ] || die "release manifest is incomplete"
    DOMAIN="$manifest_domain"
    validate_domain
    assert_manifest_release_ref
    assert_prepared_pair "$worktree" "$parent_sha"
    printf 'dry_run=local-preparation\ntask_id=%s\ndomain=%s\nparent_commit=%s\ncanvas_commit=%s\nstatus=ready-for-build-host-preflight\nremote_actions=none\n' "$TASK_ID" "$DOMAIN" "$parent_sha" "$(canvas_gitlink_sha "$parent_sha")"
}

main() {
    local command="${1:-}"
    [ -n "$command" ] || {
        usage
        exit 1
    }
    shift
    case "$command" in
        profile)
            parse_common_args "$@"
            profile
            ;;
        prepare-worktree)
            parse_common_args "$@"
            prepare_worktree
            ;;
        prepare-matrix)
            parse_matrix_args "$@"
            prepare_matrix
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
