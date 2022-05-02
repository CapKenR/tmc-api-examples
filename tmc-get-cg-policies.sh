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

OPTIONS=c:ht:u:
LONGOPTS=cluster-group:,help,api-token:,tmc-url:

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
            echo "Usage: $0 --tmc-url example.tmc.cloud.vmware.com --api-token 123-abc-456-def --cluster-group my-cluster-group"
            echo ""
            echo "Command line options for $0:"
            echo "  -c, --cluster-group <my-cluster-group>       Name of the cluster group to query for policies"
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

# Find the CSP endpoint
CSP_ENDPOINT=https://console.cloud.vmware.com
 
# Aquire access token from CSP
CSP_ACCESS_TOKEN=$(curl -sSX POST ${CSP_ENDPOINT}/csp/gateway/am/api/auth/api-tokens/authorize\?refresh_token\=${API_TOKEN} | jq -r .access_token)

# Get policies
POLICIES_JSON=$(curl -sSX GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies")

# For each policy
jsonData=$(echo ${POLICIES_JSON} | jq -c '.[]')
for row in $(echo "${jsonData}" | jq -r '.[] | @base64'); do
    _jq() {
     echo "${row}" | base64 --decode | jq -r "${1}"
    }

    name=$(_jq '.fullName.name')
    type=$(_jq '.spec.type')
    recipe=$(_jq '.spec.recipe')

    echo "Policy $name"
    curl -sSX GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies/${name}" | jq .
    echo "Recipe $recipe of Type $type"
    curl -sSX GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/policy/types/${type}/recipes/${recipe}" | jq .
    echo
    # for each policy template in recipe.spec.policyTemplates[] use (name part of) rid to get policy template
    # curl -sSX GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/policy/templates/${rid}" | jq .

done
