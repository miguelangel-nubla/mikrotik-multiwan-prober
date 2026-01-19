#!/bin/bash
set -euo pipefail

ROUTER_IP=$1
TABLE_NAME=use_$2 
USERNAME="homeassistant"
KEYFILE="/ssl/ssh/id_rsa"

# Keep your multiline script here for readability
RAW_CMD=$(cat << 'EOF'
{
    :local tableName "TABLE_NAME_HOLDER";
    :local vpsIP [/ip firewall address-list get [find list="IP_ECHO_TARGET"] address];
    :local targetPort [/ip firewall mangle get [find new-routing-mark=$tableName] dst-port];
    :put ([/tool fetch url="http://$vpsIP:$targetPort" output=user as-value]->"data");
}
EOF
)

# 1. Replace the placeholder with the argument
# 2. Collapse newlines and tabs into a single line
# 3. Use semi-colons (added above) to ensure MikroTik separates the local variables
PREPPED_CMD=$(echo "$RAW_CMD" | tr -d '\n\t' | sed 's/TABLE_NAME_HOLDER/'"$TABLE_NAME"'/' | sed 's/  */ /g')

ERR_FILE=$(mktemp)

# Disable exit-on-error for the SSH call
set +e
FETCH_OUTPUT=$(ssh -i ${KEYFILE} \
    -o MACs=hmac-sha2-256 \
    -o ConnectTimeout=10 \
    -o BatchMode=yes \
    -o "UserKnownHostsFile=/ssl/ssh/hostkey_${ROUTER_IP}" \
    ${USERNAME}@${ROUTER_IP} \
    "$PREPPED_CMD" 2>"$ERR_FILE")

SSH_EXIT_CODE=$?
set -e

if [ $SSH_EXIT_CODE -eq 0 ] && [ -n "$FETCH_OUTPUT" ]; then
    # SUCCESS: Output IP
    echo "$FETCH_OUTPUT" | tr -d '\r' | tail -n 1
    rm -f "$ERR_FILE"
    exit 0
else
    # FAILURE: Capture error from stderr file or stdout variable
    # MikroTik CLI errors usually land in the FETCH_OUTPUT variable (stdout)
    if [ -n "$FETCH_OUTPUT" ]; then
        ERROR_TEXT="$FETCH_OUTPUT"
    elif [ -s "$ERR_FILE" ]; then
        ERROR_TEXT=$(cat "$ERR_FILE")
    else
        ERROR_TEXT="Connection failed or unknown error"
    fi

    echo "Error: $(echo "$ERROR_TEXT" | tr -d '\r' | tr '\n' ' ')" >&2
    rm -f "$ERR_FILE"
    exit 1
fi