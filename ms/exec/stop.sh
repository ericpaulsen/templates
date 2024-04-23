#!/usr/bin/env bash

set -euo pipefail

if [ -z "$PROCESS_NAME" ]; then
	echo "Must provide PROCESS_NAME"
	exit 1
fi

# We have this little script so that we don't exit code 1 if we fail to find the process
# but we will if we fail to kill the process.
if pgrep -f "$PROCESS_NAME" > /dev/null; then
	pkill -f "$PROCESS_NAME"
fi
