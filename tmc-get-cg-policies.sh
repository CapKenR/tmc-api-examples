#!/bin/bash

# This script will get all the policies found in the the named cluster group (-c option).
# It requires an api token (-t) and the TMC URL (-u) to be able to retrieve policy data.
# It will also retrieve the recipe used for each policy and will get all the templates
#  that are referenced by the recipe.

# The results will be found in files in the following PATH
SAVE_DIR=/tmp

# VARIABLES
PCOUNT=0
RCOUNT=0
TCOUNT=0

if [[ -d $SAVE_DIR ]]; then
    echo $SAVE_DIR exists.
else
    echo Creataing $SAVE_DIR
    mkdir $SAVE_DIR
fi

# Functions...
_jq() {
     echo "${row}" | base64 --decode | jq -r "${1}"
}

###################### Get Command Line Args ######################3
GETOPTS=true
while $GETOPTS; do
    case "$1" in
        -c|--cluster-group)
            CLUSTER_GROUP="$2"
            shift 2
            ;;
        -d|--policy-directory)
            SAVE_DIR="$2"
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
            echo "Usage: $0 --tmc-url example.tmc.cloud.vmware.com --api-token 123-abc-456-def --cluster-group my-cluster-group"
            echo ""
            echo "Command line options for $0:"
            echo "  -c, --cluster-group <my-cluster-group>       Name of the cluster group to query for policies"
            echo "  -d, --policy-directory <policy directory>    Name of the directory into which policy files will go."
            echo "  -u, --tmc-url <example.tmc.cloud.vmware.com> TMC URL"
            echo "  -t, --api-token <123-abc-456-def>            API token for accessing CSP"
            echo "  -h, --help    Help"
            echo ""
            exit
            ;;
        *)
            echo "Invalid argument. Use $0 -h to see help page."
            exit 3
            ;;
    esac
    if [[ -z $1 ]]; then
        GETOPTS=false
    fi
done

if [[ -d $SAVE_DIR ]]; then
    echo "Policy directory looks good: $SAVE_DIR."
else
    mkdir $SAVE_DIR
    if [[ -d $SAVE_DIR ]]; then
        echo "Policy directory created and looks good: $SAVE_DIR."
    else
        echo "Policy directory can't be created."
        exit 1
    fi
fi

INDEX_FILE="${SAVE_DIR}/README.md"

# Find the CSP endpoint
CSP_ENDPOINT=https://console.cloud.vmware.com
 
# Aquire access token from CSP
echo "Getting access token..."
CSP_ACCESS_TOKEN=$(curl -skd "refresh_token=${API_TOKEN}" ${CSP_ENDPOINT}/csp/gateway/am/api/auth/api-tokens/authorize 2>/dev/null | jq -r .access_token)

# Get policy list
echo "Getting list of policies for cluster group $CLUSTER_GROUP..."
POLICIES_JSON=$(curl -sk GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies" 2>/dev/null)
echo "# Policies for Cluster $CLUSTER_NAME" > $INDEX_FILE
echo >> $INDEX_FILE
echo "This file contains the list of policies and supporting objects recipies and templates" >> $INDEX_FILE
echo "" >> $INDEX_FILE
echo ======== | tee -a $INDEX_FILE
echo Policies | tee -a $INDEX_FILE
echo ======== | tee -a $INDEX_FILE

# For each policy
jsonData=$(echo ${POLICIES_JSON} | jq -c '.[]')
for row in $(echo "${jsonData}" | jq -r '.[] | @base64'); do

    name=$(_jq '.fullName.name')
    type=$(_jq '.spec.type')
    recipe=$(_jq '.spec.recipe')

    echo "$name" | tee -a $INDEX_FILE
    PCOUNT=$(expr $PCOUNT + 1)
    POLICY_DETAILS=$(curl -sk GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies/${name}" 2>/dev/null)
    echo $POLICY_DETAILS | jq . > $SAVE_DIR/policy:${name}.json

    echo "   Recipe: $recipe (type: $type)" | tee -a $INDEX_FILE
    RECIPE_DETAILS=$(curl -sk GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/policy/types/${type}/recipes/${recipe}" 2>/dev/null)
    RCOUNT=$(expr $RCOUNT + 1)
    echo $RECIPE_DETAILS | jq . > $SAVE_DIR/recipe:${recipe}_${type}.json

    # Now... to get all the templates referenced by this policy, I'll have to loop through them all getting them one-by-one...
    POLICYTEMPLATES=$(echo ${RECIPE_DETAILS} | jq -c '.recipe.spec.policyTemplates')
    if [[ $POLICYTEMPLATES != null ]]; then
        for row in $(echo "${POLICYTEMPLATES}" | jq -r '.[] | @base64'); do
            RID=$(_jq '.rid')
            TCOUNT=$(expr $TCOUNT + 1)

            # The rid contains the template name and the org ID. Split those out.
            ORGID=$(echo $RID | awk -F: '{print $3}')
            TEMPLATE_NAME=$(echo $RID | awk -F: '{print $4}')

            # Get the template that this RID points to ...
            echo "     Template: $TEMPLATE_NAME" | tee -a $INDEX_FILE
            TEMPLATE_DETAILS=$(curl -sk GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/policy/templates/${TEMPLATE_NAME}?orgId=${ORGID}" 2>/dev/null)
            echo "$TEMPLATE_DETAILS" | jq . > $SAVE_DIR/template:${TEMPLATE_NAME}.json
        done
    fi
done
echo ========================
echo "Total Policies: $PCOUNT"
echo "      Recipies: $RCOUNT"
echo "      Templates: $TCOUNT"
echo
echo "See $SAVE_DIR for json files."
