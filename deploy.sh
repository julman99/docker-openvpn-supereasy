#!/bin/bash
set -e

VERSION="$1"
PUSH=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH="--push"
            shift
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "Usage: ./deploy.sh <version> [--push]"
    exit 3
fi

if [ -n "$PUSH" ]; then
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        echo "Error: You have uncommitted changes. Please commit or stash them before pushing."
        exit 1
    fi

    # Check for unpushed commits
    if [ -n "$(git log origin/master..HEAD)" ]; then
        echo "Error: You have unpushed commits. Please push them before tagging and pushing the image."
        exit 1
    fi

    git tag "v$VERSION"
fi

docker buildx build --platform=linux/amd64,linux/arm/v6,linux/arm/v7,linux/arm64,linux/386 . \
    -t "julman99/openvpn-supereasy:$VERSION" \
    -t julman99/openvpn-supereasy:latest \
    $PUSH
