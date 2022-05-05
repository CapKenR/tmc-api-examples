#!/bin/bash

# This script deletes a policy

# Parse the arguments...
GETOPTS=true
DRY_RUN=false
while [[ $GETOPTS == true ]]; do
    case "$1" in
        -c|--cluster-group)
            CLUSTER_GROUP="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift 1
            ;;
        -p|--policy)
            POLICY_NAME="$2"
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
            echo "Usage: $0 --tmc-url example.tmc.cloud.vmware.com --api-token 123-abc-456-def --cluster-group my-cluster-group --policy-file my-policy.json"
            echo ""
            echo "Command line options for $0:"
            echo "  -c, --cluster-group <my-cluster-group>       Name of the cluster group to query for policies"
            echo "  -d, --dry-run                                Just view what would be done. Don't delete the policy."
            echo "  -p, --policy <my-policy>                     Name of the policy to delete"
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

# Get policy
echo "Policy $POLICY_NAME"
curl -ksSX GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies/${POLICY_NAME}" | jq .

# Delete the policy
if [ $DRY_RUN == true ]; then
    echo "The policy \"${POLICY_NAME}\" in cluster group \"${CLUSTER_GROUP}\" would be deleted but --dry-run was specified in the command."
else
    echo "Deleting policy \"${POLICY_NAME}\" in cluster group \"${CLUSTER_GROUP}\"."
    curl -ks -X DELETE -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies/${POLICY_NAME}" | jq .
fi
