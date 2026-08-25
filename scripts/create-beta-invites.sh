#!/bin/sh
set -eu

COUNT=${1:-1}
LABEL=${2:-Friend}

case "$COUNT" in
    ''|*[!0-9]*) echo "Count must be a number from 1 to 50." >&2; exit 1 ;;
esac
if [ "$COUNT" -lt 1 ] || [ "$COUNT" -gt 50 ]; then
    echo "Count must be from 1 to 50." >&2
    exit 1
fi

ADMIN_SECRET=$(security find-generic-password -w \
    -s com.nandanadileep.tictic.backend \
    -a admin-secret)

PAYLOAD=$(jq -nc --argjson count "$COUNT" --arg label "$LABEL" \
    '{count: $count, label: $label}')

curl -fsS -X POST https://tictic-api.vercel.app/api/admin/invites \
    -H "Authorization: Bearer $ADMIN_SECRET" \
    -H "Content-Type: application/json" \
    --data "$PAYLOAD" | jq -r '.invites[]'
