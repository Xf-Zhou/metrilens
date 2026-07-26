#!/bin/zsh
set -euo pipefail

repo_dir=${1:-}
version=${2:-}
archive=${3:-}
checksum=${4:-}
mode=${5:-}

if [[ -z "$repo_dir" ||
      -z "$version" ||
      -z "$archive" ||
      -z "$checksum" ||
      ("$mode" != "--publish" && "$mode" != "--publish-from-actions") ]]; then
  print -u2 "publish_release.sh is an internal release helper"
  exit 2
fi

tag="v$version"
if [[ "$mode" == "--publish-from-actions" ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != "true" ||
        "${GITHUB_REF_TYPE:-}" != "tag" ||
        "${GITHUB_REF_NAME:-}" != "$tag" ]]; then
    print -u2 -- "--publish-from-actions must run in GitHub Actions from tag $tag"
    exit 1
  fi
fi

cd "$repo_dir"
if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 "Publishing requires a clean worktree"
  exit 1
fi

head_commit=$(git rev-parse HEAD)
remote_peeled=$(
  git ls-remote --tags origin "refs/tags/$tag^{}" | awk 'NR == 1 { print $1 }'
)
remote_direct=$(
  git ls-remote --tags origin "refs/tags/$tag" | awk 'NR == 1 { print $1 }'
)
remote_commit=${remote_peeled:-$remote_direct}
if [[ -n "$remote_commit" && "$remote_commit" != "$head_commit" ]]; then
  print -u2 "Remote tag $tag points to $remote_commit, expected $head_commit"
  exit 1
fi

if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
  if [[ "$(git rev-list -n 1 "$tag")" != "$head_commit" ]]; then
    print -u2 "Existing tag $tag does not point to HEAD"
    exit 1
  fi
elif [[ "$mode" == "--publish-from-actions" ]]; then
  print -u2 "GitHub Actions checkout is missing expected tag $tag"
  exit 1
else
  git tag -a "$tag" -m "Metrilens $tag"
fi

if [[ "$mode" == "--publish-from-actions" ]]; then
  if [[ -z "$remote_commit" ]]; then
    print -u2 "Remote tag $tag does not exist"
    exit 1
  fi
elif [[ -z "$remote_commit" ]]; then
  git push origin "$tag"
  print "Pushed $tag; GitHub Actions now owns publishing this release"
  exit 0
fi

verification_dir=$(mktemp -d "${TMPDIR:-/tmp}/metrilens-release.XXXXXX")
cleanup_verification() {
  rm -rf "$verification_dir"
}
trap cleanup_verification EXIT

verify_remote_assets() {
  if ! gh release download "$tag" \
    --dir "$verification_dir" \
    --pattern "${archive:t}" \
    --pattern "${checksum:t}" \
    --clobber; then
    print -u2 "Could not download both expected assets for GitHub release $tag"
    return 1
  fi

  if [[ ! -f "$verification_dir/${archive:t}" ||
        ! -f "$verification_dir/${checksum:t}" ]]; then
    print -u2 "GitHub release $tag is missing an expected asset"
    return 1
  fi

  if ! cmp "$archive" "$verification_dir/${archive:t}" ||
     ! cmp "$checksum" "$verification_dir/${checksum:t}"; then
    print -u2 "GitHub release $tag assets differ from the local package"
    return 1
  fi
}

if [[ "$mode" == "--publish" ]]; then
  if gh release view "$tag" >/dev/null 2>&1; then
    release_is_draft=$(gh release view "$tag" --json isDraft --jq .isDraft)
    if [[ "$release_is_draft" == "false" ]]; then
      if ! verify_remote_assets; then
        print -u2 "Published release $tag was left unchanged; resolve it manually"
        exit 1
      fi
      print "GitHub release $tag is already published with matching assets"
      exit 0
    fi
  fi

  gh workflow run release.yml --ref "$tag" -f "tag=$tag"
  print "Requested the GitHub Actions release workflow for $tag"
  exit 0
fi

if gh release view "$tag" >/dev/null 2>&1; then
  release_tag=$(gh release view "$tag" --json tagName --jq .tagName)
  if [[ "$release_tag" != "$tag" ]]; then
    print -u2 "GitHub release tag is $release_tag, expected $tag"
    exit 1
  fi

  release_is_draft=$(gh release view "$tag" --json isDraft --jq .isDraft)
  if [[ "$release_is_draft" == "false" ]]; then
    if ! verify_remote_assets; then
      print -u2 "Published release $tag was left unchanged; resolve it manually"
      exit 1
    fi
    print "GitHub release $tag is already published with matching assets"
    exit 0
  fi
else
  gh release create "$tag" \
    --title "Metrilens $tag" \
    --generate-notes \
    --draft \
    --verify-tag
fi

release_tag=$(gh release view "$tag" --json tagName --jq .tagName)
if [[ "$release_tag" != "$tag" ]]; then
  print -u2 "GitHub release tag is $release_tag, expected $tag"
  exit 1
fi

gh release upload "$tag" "$archive" "$checksum" --clobber

verify_remote_assets

gh release edit "$tag" --draft=false
release_is_draft=$(gh release view "$tag" --json isDraft --jq .isDraft)
if [[ "$release_is_draft" != "false" ]]; then
  print -u2 "GitHub release $tag is still a draft after publishing"
  exit 1
fi

print "Published GitHub release $tag"
