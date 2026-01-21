#!/bin/bash
set -euo pipefail

ROUTER_IP=$1
TABLE_NAME=use_$2 
USERNAME="homeassistant"
KEYFILE="/ssl/ssh/id_rsa"

# We use :do {} on-error {} to handle the timeout/failure inside RouterOS.
# If it fails, we print a specific string 'FETCH_FAILED' and /quit.
RAW_CMD=$(cat << 'EOF'
:do {
    :local tableName "TABLE_NAME_HOLDER";
    :local vpsIP [/ip firewall address-list get [find list="IP_ECHO_TARGET"] address];
    :local targetPort [/ip firewall mangle get [find new-routing-mark=$tableName] dst-port];
    :local result ([/tool fetch url="http://$vpsIP:$targetPort" output=user as-value duration=10s]);
    :put ($result->"data");
} on-error={
    :put "FETCH_FAILED";
    /quit;
}
EOF
)

# 1. Replace the placeholder with the argument
# 2. Collapse newlines and tabs for SSH compatibility
PREPPED_CMD=$(echo "$RAW_CMD" | tr -d '\n\t' | sed 's/TABLE_NAME_HOLDER/'"$TABLE_NAME"'/' | sed 's/  */ /g')

ERR_FILE=$(mktemp)

# Disable exit-on-error for the SSH call to handle custom error logic
set +e
FETCH_OUTPUT=$(ssh -i ${KEYFILE} \
    -o MACs=hmac-sha2-256 \
    -o ConnectTimeout=15 \
    -o BatchMode=yes \
    -o "UserKnownHostsFile=/ssl/ssh/hostkey_${ROUTER_IP}" \
    ${USERNAME}@${ROUTER_IP} \
    "$PREPPED_CMD" 2>"$ERR_FILE")

SSH_EXIT_CODE=$?
set -e

# Validate the output:
# 1. SSH must return code 0
# 2. Output must not be empty
# 3. Output must not contain our custom "FETCH_FAILED" string
if [ $SSH_EXIT_CODE -eq 0 ] && [ -n "$FETCH_OUTPUT" ] && [[ ! "$FETCH_OUTPUT" == *"FETCH_FAILED"* ]]; then
    # SUCCESS: Extract the last line (the IP or data)
    CLEAN_OUTPUT=$(echo "$FETCH_OUTPUT" | tr -d '\r' | tail -n 1)

    echo "$CLEAN_OUTPUT"
    rm -f "$ERR_FILE"
    exit 0
else
    # FAILURE logic
    if [[ "$FETCH_OUTPUT" == *"FETCH_FAILED"* ]]; then
        ERROR_TEXT="MikroTik /tool fetch timed out or the remote host refused the connection."
    elif [ -s "$ERR_FILE" ]; then
        ERROR_TEXT=$(cat "$ERR_FILE")
    else
        ERROR_TEXT="Unknown SSH error or empty response. Output: $FETCH_OUTPUT"
    fi

    echo "Error: $(echo "$ERROR_TEXT" | tr -d '\r' | tr '\n' ' ')" >&2
    rm -f "$ERR_FILE"
    exit 1
fi