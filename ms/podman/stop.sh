#!/usr/bin/env bash

set -euo pipefail

if [ -z "$CONTAINER_NAME" ]; then
	echo "Must provide CONTAINER_NAME"
	exit 1
fi

if podman container inspect "$CONTAINER_NAME" > /dev/null 2>&1; then
	podman rm -f "$CONTAINER_NAME"
fi
