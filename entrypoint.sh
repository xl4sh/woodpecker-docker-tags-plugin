#!/usr/bin/env bash

set -euo pipefail

commands="${PLUGIN_TAGS}"
tags_file="${PLUGIN_TAGS_FILE:-.tags}"

sanitize_and_write_tag() {
  local lowercased_tag sanitized_tag truncated_tag

  lowercased_tag="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  sanitized_tag="${lowercased_tag//[^a-zA-Z0-9\-\_\.]/-}"
  truncated_tag="${sanitized_tag:0:128}"

  echo "$truncated_tag" >>"$tags_file"
}

handle_branch() {
  local prefix=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -p | --prefix)
      prefix="$2"
      shift
      ;;
    *)
      echo "Invalid option '$1'." >&2
      exit 1
      ;;
    esac
    shift
  done

  sanitize_and_write_tag "$prefix$CI_COMMIT_BRANCH"
}

handle_cron() {
  [[ "$CI_PIPELINE_EVENT" != "cron" ]] && return

  local format="%Y%m%d"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -f | --format)
      format="$2"
      shift
      ;;
    *)
      echo "Invalid option '$1'." >&2
      exit 1
      ;;
    esac
    shift
  done

  sanitize_and_write_tag "$(date +"$format")"
}

handle_edge() {
  [[ "$CI_PIPELINE_EVENT" != "push" ]] && return

  local value="edge"
  local branch="$CI_REPO_DEFAULT_BRANCH"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -v | --value)
      value="$2"
      shift
      ;;
    -b | --branch)
      branch="$2"
      shift
      ;;
    *)
      echo "Invalid option '$1'." >&2
      exit 1
      ;;
    esac
    shift
  done

  [[ "$CI_COMMIT_BRANCH" != "$branch" ]] && return

  sanitize_and_write_tag "$value"
}

handle_pr() {
  [[ "$CI_PIPELINE_EVENT" != "pull_request" ]] && return

  local prefix="pr-"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -p | --prefix)
      prefix="$2"
      shift
      ;;
    *)
      echo "Invalid option '$1'." >&2
      exit 1
      ;;
    esac
    shift
  done

  sanitize_and_write_tag "$prefix$CI_COMMIT_PULL_REQUEST"
}

handle_raw() {
  local value=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -v | --value)
      value="$2"
      shift
      ;;
    *)
      echo "Invalid option '$1'." >&2
      exit 1
      ;;
    esac
    shift
  done

  [[ -z "$value" ]] && {
    echo "Error: --value is required." >&2
    exit 1
  }

  sanitize_and_write_tag "$value"
}

# Reference: https://gist.github.com/bitmvr/9ed42e1cc2aac799b123de9fdc59b016
parse_semver() {
  VERSION="${1#[vV]}"
  VERSION_MAJOR="${VERSION%%.*}"
  VERSION_MINOR_PATCH="${VERSION#*.}"
  VERSION_MINOR="${VERSION_MINOR_PATCH%%.*}"
  VERSION_PATCH_PRE_RELEASE="${VERSION_MINOR_PATCH#*.}"
  VERSION_PATCH="${VERSION_PATCH_PRE_RELEASE%%[-+]*}"
  VERSION_PRE_RELEASE=""

  if [[ "$VERSION" == *-* ]]; then
    VERSION_PRE_RELEASE="${VERSION#*-}"
    VERSION_PRE_RELEASE="${VERSION_PRE_RELEASE%%+*}"
  fi

  export VERSION VERSION_MAJOR VERSION_MINOR VERSION_PATCH VERSION_PRE_RELEASE
}

handle_semver() {
  [[ "$CI_PIPELINE_EVENT" != "tag" ]] && return

  local format="{{version}}"
  local value="$CI_COMMIT_TAG"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -f | --format)
      format="$2"
      shift
      ;;
    -v | --value)
      value="$2"
      shift
      ;;
    *)
      echo "Invalid option '$1'." >&2
      exit 1
      ;;
    esac
    shift
  done

  parse_semver "$value"
  sanitize_and_write_tag "$(
    echo "$format" |
      sed "s/{{raw}}/${value}/" |
      sed "s/{{version}}/${VERSION}/" |
      sed "s/{{major}}/${VERSION_MAJOR}/" |
      sed "s/{{minor}}/${VERSION_MINOR}/" |
      sed "s/{{patch}}/${VERSION_PATCH}/"
  )"
}

handle_sha() {
  local length=8
  local prefix=sha-

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -l | --long)
      length=40
      ;;
    -p | --prefix)
      prefix="${2//[\"\']/}"
      shift
      ;;
    *)
      echo "Invalid option '$1'." >&2
      exit 1
      ;;
    esac
    shift
  done

  sanitize_and_write_tag "$prefix${CI_COMMIT_SHA:0:$length}"
}

handle_tag() {
  [[ "$CI_PIPELINE_EVENT" != "tag" ]] && return

  sanitize_and_write_tag "$CI_COMMIT_TAG"
}

handle_command() {
  [[ -z "$1" ]] && return

  # shellcheck disable=SC2086
  set -- $1

  local type="$1"
  shift

  case "$type" in
  branch) handle_branch "$@" ;;
  cron) handle_cron "$@" ;;
  edge) handle_edge "$@" ;;
  pr) handle_pr "$@" ;;
  raw) handle_raw "$@" ;;
  semver) handle_semver "$@" ;;
  sha) handle_sha "$@" ;;
  tag) handle_tag "$@" ;;
  \#) ;;
  *)
    echo "Invalid type '$type'." >&2
    exit 1
    ;;
  esac
}

remove_duplicate_tags() {
  awk '!seen[$0]++' "$tags_file" >/tmp/.tags
  mv /tmp/.tags "$tags_file"
}

main() {
  while IFS= read -r command; do
    (
      handle_command "$command"
    )
  done <<<"$commands"

  remove_duplicate_tags
}

main
