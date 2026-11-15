#!/bin/bash
# Builds the universal ZIP, publishes it as a GitHub release and points the Homebrew cask at it.
# Usage: bash publish-release.sh [VERSION]   (defaults to the VERSION file)
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"
TAG="v$VERSION"
ARCHIVE="dist/Linory-$VERSION-universal.zip"
CASK="Casks/linory.rb"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean; commit or stash first." >&2
  exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists." >&2
  exit 1
fi

bash build-release.sh "$VERSION"
SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"

# Release notes: the top section of RELEASE_NOTES.md, up to the first separator.
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
awk '/^---$/{exit} {print}' RELEASE_NOTES.md > "$NOTES"

gh release create "$TAG" "$ARCHIVE" --title "Linory $TAG" --notes-file "$NOTES" --target "$(git rev-parse HEAD)"

sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git add "$CASK"
git commit -m "chore: update Homebrew cask to $VERSION"
git push
echo "Published $TAG; brew upgrade --cask linory now installs it."
