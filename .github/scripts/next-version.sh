#!/usr/bin/env bash
# Prints the next release version from the repository's tags.
#
# Without an argument, prints the next minor version with the patch reset,
# starting at 2.0.0 for legacy 1.x tags. Prints nothing when HEAD already has
# a release tag, so reruns do not publish twice.
# With an explicit MAJOR.MINOR.PATCH argument, validates that it is a new,
# increasing version of at least 2.0.0 for major or patch releases.
set -euo pipefail

readonly minimum_major=2
readonly requested="${1:-}"

# Prints 1, 0, or -1 when the first version is greater, equal, or smaller.
compare() {
  local -a left right
  IFS=. read -r -a left <<< "$1"
  IFS=. read -r -a right <<< "$2"
  for index in 0 1 2; do
    if ((left[index] > right[index])); then
      echo 1
      return
    fi
    if ((left[index] < right[index])); then
      echo -1
      return
    fi
  done
  echo 0
}

# Accepts legacy MAJOR.MINOR tags as MAJOR.MINOR.0.
normalize() {
  if [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[4]:-0}"
  fi
}

latest=0.0.0
while read -r tag; do
  version=$(normalize "$tag")
  if [[ -n "$version" && $(compare "$version" "$latest") == 1 ]]; then
    latest=$version
  fi
done < <(git tag --list)

if [[ -n "$requested" ]]; then
  if ! [[ "$requested" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Version must be MAJOR.MINOR.PATCH without a prefix: $requested" >&2
    exit 1
  fi
  if ((BASH_REMATCH[1] < minimum_major)); then
    echo "Version must be at least $minimum_major.0.0: $requested" >&2
    exit 1
  fi
  if [[ $(compare "$requested" "$latest") != 1 ]]; then
    echo "Version must be greater than the latest release $latest: $requested" >&2
    exit 1
  fi
  echo "$requested"
  exit 0
fi

while read -r tag; do
  if [[ -n $(normalize "$tag") ]]; then
    exit 0
  fi
done < <(git tag --points-at HEAD)

IFS=. read -r major minor _ <<< "$latest"
if ((major < minimum_major)); then
  echo "$minimum_major.0.0"
else
  echo "$major.$((minor + 1)).0"
fi
