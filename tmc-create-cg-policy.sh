#!/bin/bash
PWD=`pwd`
SCRIPT_DIR=`dirname "$0"`

# saner programming env: these switches turn some bugs into errors
#kdr set -o errexit -o pipefail -o noclobber -o nounset
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo "I’m sorry, `getopt --test` failed in this environment."
    exit 1
fi

OPTIONS=c:fht:u:
LONGOPTS=cluster-group:,policy-file:,help,api-token:,tmc-url:

# -use ! and PIPESTATUS to get exit code with errexit set
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -c|--cluster-group)
            c="$2"
            shift 2
            ;;
        -f|--policy-file)
            f="$2"
            shift 2
            ;;
        -t|--api-token)
            t="$2"
            shift 2
            ;;
        -u|--tmc-url)
            u="$2"
            shift 2
            ;;
        -h|--help)
            echo ""
            echo "Usage: $0 --tmc-url example.tmc.cloud.vmware.com --api-token 123-abc-456-def --cluster-group my-cluster-group --policy-file my-policy.json"
            echo ""
            echo "Command line options for $0:"
            echo "  -c, --cluster-group <my-cluster-group>       Name of the cluster group to query for policies"
            echo "  -f, --policy-file <my-policy.json>           Filename of your policy in JSON format"
            echo "  -u, --tmc-url <example.tmc.cloud.vmware.com> TMC URL"
            echo "  -t, --api-token <123-abc-456-def>            API token for accessing CSP"
            echo "  -h, --help    Help"
            echo ""
            exit
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 3
            ;;
    esac
done

export API_ENDPOINT=$u
export API_TOKEN=$t
export CLUSTER_GROUP=$c
export POLICY_FILE=$f

# Find the CSP endpoint
CSP_ENDPOINT=https://console.cloud.vmware.com
 
# Aquire access token from CSP
CSP_ACCESS_TOKEN=$(curl -sSX POST ${CSP_ENDPOINT}/csp/gateway/am/api/auth/api-tokens/authorize\?refresh_token\=${API_TOKEN} | jq -r .access_token)

# Get policy
POLICY_JSON=$(cat ${POLICY_FILE} | jq -r .)

# Create the policy in the specified cluster group
curl -s -d "${POLICY_JSON}" -H "Content-Type: application/json" -X POST -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies" | jq .
