#!/bin/bash

# This script gets all current insights from a TMC system.

# Parse the arguments...
GETOPTS=true
DRY_RUN=false
while [[ $GETOPTS == true ]]; do
    case "$1" in
        -c|--cluster-group)
            CLUSTER_GROUP="$2"
            shift 2
            ;;
        -t|--api-token)
            API_TOKEN="$2"
            shift 2
            ;;
        -u|--tmc-url)
            API_ENDPOINT="$2"
            shift 2
            ;;
        -h|--help)
            echo ""
            echo "Usage: $0 --tmc-url example.tmc.cloud.vmware.com --api-token 123-abc-456-def"
            echo ""
            echo "Command line options for $0:"
            echo "  -u, --tmc-url <example.tmc.cloud.vmware.com> TMC URL"
            echo "  -t, --api-token <123-abc-456-def>            API token for accessing CSP"
            echo "  -h, --help    Help"
            echo ""
            exit
            ;;
        *)
            echo "Invalid argument. Please use $0 -h to view the argument list."
            exit 3
            ;;
    esac
    if [[ -z $1 ]]; then
        GETOPTS=false
    fi
done

# Find the CSP endpoint
CSP_ENDPOINT=https://console.cloud.vmware.com
 
# Aquire access token from CSP
CSP_ACCESS_TOKEN=$(curl -kX POST ${CSP_ENDPOINT}/csp/gateway/am/api/auth/api-tokens/authorize\?refresh_token\=${API_TOKEN} 2>/dev/null | jq -r .access_token)

# Get the list of insights
curl -ksSX GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/policy/insights" | jq .

