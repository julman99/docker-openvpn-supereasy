#!/bin/bash
set -e

VERSION="$1"

if [ -z "$VERSION" ]; then
        echo "Usage ./deploy.sh <version>"
        exit 3
    fi

if [ "$OPENVPN_PORT_UDP" == "off" ];then
    OPENVPN_PORT_UDP=
fi

git tag v$VERSION
docker buildx build --platform=linux/amd64,linux/arm/v6,linux/arm/v7,linux/arm/v8,linux/386 . -t julman99/openvpn-supereasy:$VERSION  -t julman99/openvpn-supereasy:latest --push
