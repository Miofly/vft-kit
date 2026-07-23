#!/bin/bash
# Create a release: build, notarize, create DMG, optionally sign for Sparkle, upload to GitHub, update website
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PING_ISLAND_BUILD_DIR:-$PROJECT_DIR/build/release}"
EXPORT_PATH="$BUILD_DIR/export"
RELEASE_DIR="${PING_ISLAND_RELEASE_DIR:-$PROJECT_DIR/releases/signed}"
NOTES_DIR="$PROJECT_DIR/releases/notes"

# Website repo for auto-updating appcast
WEBSITE_DIR="${PING_ISLAND_WEBSITE:-$PROJECT_DIR/../AIHelper-website}"
WEBSITE_PUBLIC="$WEBSITE_DIR/public"

APP_PATH="$EXPORT_PATH/ai-helper.app"
APP_NAME="AIHelper"
NOTARY_PROFILE="${PING_ISLAND_NOTARY_KEYCHAIN_PROFILE:-AIHelper}"
RELEASE_TAG_PREFIX="${PING_ISLAND_RELEASE_TAG_PREFIX:-ai-helper-v}"

infer_github_repo() {
    if [ -n "${PING_ISLAND_GITHUB_REPO:-}" ]; then
        echo "$PING_ISLAND_GITHUB_REPO"
        return 0
    fi

    local remote_url
    remote_url=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)

    if [[ "$remote_url" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

GITHUB_REPO="$(infer_github_repo || true)"

echo "=== Creating Release ==="
echo ""

export PING_ISLAND_BUILD_DIR="$BUILD_DIR"
export PING_ISLAND_RELEASE_DIR="$RELEASE_DIR"
export PING_ISLAND_GENERATE_APPCAST=1
export PING_ISLAND_NOTARY_KEYCHAIN_PROFILE="$NOTARY_PROFILE"

"$SCRIPT_DIR/package-release.sh"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
DMG_SHA256_PATH="$DMG_PATH.sha256"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
NOTES_PATH="$NOTES_DIR/$VERSION.md"
NOTES_ASSET_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.md"
APPCAST_PATH="$RELEASE_DIR/appcast/appcast.xml"
RELEASE_TAG="${RELEASE_TAG_PREFIX}${VERSION}"

if [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG not found at $DMG_PATH"
    exit 1
fi
if [ ! -f "$DMG_SHA256_PATH" ]; then
    echo "ERROR: DMG checksum not found at $DMG_SHA256_PATH"
    exit 1
fi

echo "Version: $VERSION (build $BUILD)"
echo ""

mkdir -p "$RELEASE_DIR" "$NOTES_DIR"

# ============================================
# Step 1: Create GitHub Release
# ============================================
echo "=== Step 1: Creating GitHub Release ==="

GITHUB_DOWNLOAD_URL=""

if ! command -v gh >/dev/null 2>&1; then
    echo "WARNING: gh CLI not found. Install with: brew install gh"
    echo "Skipping GitHub release."
elif [ -z "$GITHUB_REPO" ]; then
    echo "WARNING: Could not infer GitHub repository. Set PING_ISLAND_GITHUB_REPO=owner/repo to enable release upload."
    echo "Skipping GitHub release."
else
    RELEASE_ASSETS=("$DMG_PATH" "$DMG_SHA256_PATH")
    if [ -f "$ZIP_PATH" ]; then
        RELEASE_ASSETS+=("$ZIP_PATH")
    fi
    if [ -f "$NOTES_ASSET_PATH" ]; then
        RELEASE_ASSETS+=("$NOTES_ASSET_PATH")
    fi
    if [ -f "$APPCAST_PATH" ]; then
        RELEASE_ASSETS+=("$APPCAST_PATH")
    fi

    if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
        echo "Release $RELEASE_TAG already exists. Updating..."
        gh release upload "$RELEASE_TAG" "${RELEASE_ASSETS[@]}" --repo "$GITHUB_REPO" --clobber
        if [ -f "$NOTES_PATH" ]; then
            gh release edit "$RELEASE_TAG" \
                --repo "$GITHUB_REPO" \
                --title "ai-helper v$VERSION" \
                --notes-file "$NOTES_PATH"
        fi
    else
        echo "Creating release $RELEASE_TAG..."

        if [ -f "$NOTES_PATH" ]; then
            gh release create "$RELEASE_TAG" "${RELEASE_ASSETS[@]}" \
                --repo "$GITHUB_REPO" \
                --title "ai-helper v$VERSION" \
                --notes-file "$NOTES_PATH"
        else
            gh release create "$RELEASE_TAG" "${RELEASE_ASSETS[@]}" \
                --repo "$GITHUB_REPO" \
                --title "ai-helper v$VERSION" \
                --notes "## Highlights

- Download \`$(basename "$DMG_PATH")\` and install the latest ai-helper release.

## Fixes

- This fallback release note was auto-generated because no dedicated notes file was found for $RELEASE_TAG.

## Notes

- Open the DMG, drag ai-helper to Applications, and launch it normally.
- After installation, ai-helper will automatically check for updates."
        fi
    fi

    GITHUB_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/$(basename "$DMG_PATH")"
    echo "GitHub release created: https://github.com/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
    echo "Download URL: $GITHUB_DOWNLOAD_URL"
fi

echo ""

# ============================================
# Step 2: Update website appcast and deploy
# ============================================
echo "=== Step 2: Updating Website ==="

if [ -d "$WEBSITE_PUBLIC" ] && [ -f "$RELEASE_DIR/appcast/appcast.xml" ]; then
    cp "$RELEASE_DIR/appcast/appcast.xml" "$WEBSITE_PUBLIC/appcast.xml"
    if [ -f "$NOTES_ASSET_PATH" ]; then
        cp "$NOTES_ASSET_PATH" "$WEBSITE_PUBLIC/"
    fi

    if [ -n "$GITHUB_DOWNLOAD_URL" ]; then
        sed -i '' "s|url=\"[^\"]*$(basename "$DMG_PATH")\"|url=\"$GITHUB_DOWNLOAD_URL\"|g" "$WEBSITE_PUBLIC/appcast.xml"
        echo "Updated appcast.xml with GitHub download URL"
    fi

    CONFIG_FILE="$WEBSITE_DIR/src/config.ts"
    if [ -n "$GITHUB_DOWNLOAD_URL" ]; then
        cat > "$CONFIG_FILE" << EOF
// Auto-updated by create-release.sh
export const LATEST_VERSION = "$VERSION";
export const DOWNLOAD_URL = "$GITHUB_DOWNLOAD_URL";
EOF
        echo "Updated src/config.ts with version $VERSION"
    fi

    cd "$WEBSITE_DIR"
    if [ -d ".git" ]; then
        git add public/appcast.xml src/config.ts
        if [ -f "$NOTES_ASSET_PATH" ]; then
            git add "public/$APP_NAME-$VERSION.md"
        fi
        if ! git diff --cached --quiet; then
            git commit -m "Update appcast for v$VERSION"
            echo "Committed appcast update"

            read -p "Push website changes to deploy? (Y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                git push
                echo "Website deployed!"
            else
                echo "Changes committed but not pushed. Run 'git push' in $WEBSITE_DIR to deploy."
            fi
        else
            echo "No changes to commit"
        fi
    else
        echo "Copied appcast.xml to $WEBSITE_PUBLIC/"
        echo "Note: Website directory is not a git repo"
    fi
    cd "$PROJECT_DIR"
else
    echo "Website directory not found or appcast not generated"
    echo "Skipping website update."
fi

echo ""
echo "=== Release Complete ==="
echo ""
echo "Files created:"
echo "  - DMG: $DMG_PATH"
if [ -f "$RELEASE_DIR/appcast/appcast.xml" ]; then
    echo "  - Appcast: $RELEASE_DIR/appcast/appcast.xml"
fi
if [ -f "$NOTES_ASSET_PATH" ]; then
    echo "  - Release notes: $NOTES_ASSET_PATH"
fi
if [ -n "$GITHUB_DOWNLOAD_URL" ]; then
    echo "  - GitHub: https://github.com/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
fi
if [ -f "$WEBSITE_PUBLIC/appcast.xml" ]; then
    echo "  - Website: $WEBSITE_PUBLIC/appcast.xml"
fi
