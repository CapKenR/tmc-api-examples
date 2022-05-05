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
            echo "Usage: $0 --tmc-url example.tmc.cloud.vmware.com --api-token 123-abc-456-def --cluster-name my-cluster-name"
            echo ""
            echo "Command line options for $0:"
            echo "  -c, --cluster-name <my-cluster-name>         Name of the cluster to query for scans"
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
export CLUSTER_NAME=$c

# Find the CSP endpoint
CSP_ENDPOINT=https://console.cloud.vmware.com
 
# Aquire access token from CSP
CSP_ACCESS_TOKEN=$(curl -sSX POST ${CSP_ENDPOINT}/csp/gateway/am/api/auth/api-tokens/authorize\?refresh_token\=${API_TOKEN} | jq -r .access_token)

# Get scans
SCANS_JSON=$(curl -sSX GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clusters/${CLUSTER_NAME}/inspection/scans")
echo Scans
echo ${SCANS_JSON} | jq .

MANAGEMENT_CLUSTER_NAME=$(echo ${SCANS_JSON} | jq -r '.scans[0].fullName.managementClusterName')
PROVISIONER_NAME=$(echo ${SCANS_JSON} | jq -r '.scans[0].fullName.provisionerName')
SCAN_NAME=$(echo ${SCANS_JSON} | jq -r '.scans[0].fullName.name')

SCAN_JSON=$(curl -sSX GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clusters/${CLUSTER_NAME}/inspection/scans/${SCAN_NAME}?fullName.managementClusterName=${MANAGEMENT_CLUSTER_NAME}&fullName.provisionerName=${PROVISIONER_NAME}")
echo Scan ${SCAN_NAME}
echo ${SCAN_JSON} | jq .

echo Failed Tests
echo ${SCAN_JSON} | jq -r '.scan.status.report.results.failed_tests' | jq .
echo
echo Warning Tests
echo ${SCAN_JSON} | jq -r '.scan.status.report.results.warn_tests' | jq .
echo
echo Passed Tests
echo ${SCAN_JSON} | jq -r '.scan.status.report.results.passed_tests' | jq .
