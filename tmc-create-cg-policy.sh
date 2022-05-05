#!/bin/bash

# This script will create a policy in TMC.
# It requires the name of the policy file, an api token (-t) and the TMC URL (-u) 
#  to be able to create the policy.
# It will also create the recipe if it doesn't exist and the templates if they
#  don't exist.
# If you want to overwrite the policies, you must specify the -o | --overwrite flag

# CONSTANTS
# CSP endpoint - URL where I send my token to get an access token for this interaction.
CSP_ENDPOINT=https://console.cloud.vmware.com

#####################################################
# Functions...
_jq() {
     echo "${row}" | base64 --decode | jq -r "${1}"
}

# VARIABLES
GETOPTS=true
DRY_RUN=false
TCOUNT=0
OVERWRITE=false
VERBOSE=false
OUTPUT=""

# Parse the arguments...
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
        -f|--policy-file)
            POLICY_FILE="$2"
            shift 2
            ;;
        -o|--overwrite)
            OVERWRITE=true
            shift 1
            ;;
        -t|--api-token)
            API_TOKEN="$2"
            shift 2
            ;;
        -u|--tmc-url)
            API_ENDPOINT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift 1
            ;;
        -h|--help)
            echo ""
            echo "Usage: $0 --tmc-url example.tmc.cloud.vmware.com --api-token 123-abc-456-def --cluster-group my-cluster-group --policy-file my-policy.json"
            echo ""
            echo "Command line options for $0:"
            echo "  -c, --cluster-group <my-cluster-group>       Name of the cluster group to query for policies"
            echo "  -d, --dry-run                                Dry run; don't make changes. Just display what would be done."
            echo "  -f, --policy-file <my-policy.json>           Filename of your policy in JSON format"
            echo "  -o, --overwrite                              Overwrite the policy even if it exists."
            echo "  -u, --tmc-url <example.tmc.cloud.vmware.com> TMC URL"
            echo "  -v, --verbose                                Verbose output. Will show results from API calls."
            echo "  -t, --api-token <123-abc-456-def>            API token for accessing CSP"
            echo "  -h, --help    Help"
            echo ""
            exit
            ;;
        *)
            echo "Invalid arguments. Please use $0 --help to view the valid arguments."
            exit 3
            ;;
    esac
    if [[ -z $1 ]];then
        GETOPTS=false
    fi
done

# Check for file existence
if [[ ! -f $POLICY_FILE ]]; then
    echo "The policy file $POLICY_FILE not found."
    exit 4
fi

# Acquire access token from CSP
CSP_ACCESS_TOKEN=$(curl -ksSX POST ${CSP_ENDPOINT}/csp/gateway/am/api/auth/api-tokens/authorize\?refresh_token\=${API_TOKEN} | jq -r .access_token)

if [[ -z $CSP_ACCESS_TOKEN ]]; then
    echo Access Token not received.
    exit 2
else
    echo Access Token received.
fi

# Get policy
POLICY_JSON=$(cat ${POLICY_FILE})
PDIR=$(dirname $POLICY_FILE)
POLICY_NAME=$(echo $POLICY_JSON | jq -r '.policy.fullName.name')
echo "Policy: $POLICY_NAME"

# Check to see if the policy is already in TMC...
POLICY_MISSING=false
POLICY_DETAILS=$(curl -sk GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies/${POLICY_NAME}" 2>/dev/null)
echo $POLICY_DETAILS | grep -q '"error":"failed'
if [[ $? -ne 0 ]]; then
    POLICY_MISSING=true
    if [[ $OVERWRITE == true ]]; then
        echo "Policy ${name} already exists but will be overwritten."
    else
        echo "Policy ${name} already exists. If you want to overwrite this policy, include the -o flag."
        exit 0
    fi
fi

# Get recipe details from this policy file...
RECIPE_NAME=$(echo $POLICY_JSON | jq -r '.policy.spec.recipe')
RECIPE_TYPE=$(echo $POLICY_JSON | jq -r '.policy.spec.type')

RECIPE_FILE=${PDIR}/recipe:${RECIPE_NAME}_${RECIPE_TYPE}.json
# Check for file existence
if [[ ! -f $RECIPE_FILE ]]; then
    echo "The recipe file $RECIPE_FILE on which this policy depends is not found."
    exit 5
else
    RECIPE_DETAILS=$(cat $RECIPE_FILE)
    # Do I need to Check to see if recipe is already in TMC?
    # At this point, we are thinking that the recipe is created when the template is created.
fi

# Get Template details from this recipe file...
POLICYTEMPLATES=$(echo $RECIPE_DETAILS | jq -c '.recipe.spec.policyTemplates')
    if [[ "${POLICYTEMPLATES}" != null ]]; then
        for row in $(echo "${POLICYTEMPLATES}" | jq -r '.[] | @base64'); do
            RID=$(_jq '.rid')
            TCOUNT=$(expr $TCOUNT + 1)

            # The rid contains the template name and the org ID. Split those out.
            ORGID=$(echo $RID | awk -F: '{print $3}')
            TEMPLATE_NAME=$(echo $RID | awk -F: '{print $4}')

            # Get the template that this RID points to ...
            TEMPLATE_FILE=${PDIR}/template:${TEMPLATE_NAME}.json
            # Check for file existence
            if [[ ! -f $TEMPLATE_FILE ]]; then
                echo "The template file $TEMPLATE_FILE on which this policy depends is not found."
                exit 6
            else
                # Does this template exist in TMC?
                TEMPLATE_DETAILS=$(curl -ks GET -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/policy/templates/${TEMPLATE_NAME}?orgId=${ORGID}" 2>/dev/null)
                CREATE_TEMPLATE=false
                TEMPLATE_MISSING=false
                echo $TEMPLATE_DETAILS | grep -q '"error":"NotFound"'
                if [[ $? -eq 0 ]]; then
                    echo Template missing. Creating $TEMPLATE_FILE template...
                    TEMPLATE_MISSING=true
                    CREATE_TEMPLATE=true
                else
                    echo "Template \"${TEMPLATE_NAME}\" is already in TMC."
                fi

                if [[ $OVERWRITE == true ]]; then
                    CREATE_TEMPLATE=true
                    if [[ $TEMPLATE_MISSING == false ]]; then
                        echo "Existing template \"${TEMPLATE_NAME}\" will be overwritten."
                    fi
                fi
                if [[ $CREATE_TEMPLATE == true ]]; then
                    TRIMMED_TEMPLATE_FILE=/tmp/template_file_$$.json
                    jq 'del(.template.meta.uid)' $TEMPLATE_FILE | jq 'del(.template.meta.resourceVersion)' | jq 'del(.template.meta.creationTime)' | jq 'del(.template.meta.updateTime)' | jq 'del(.template.fullName.orgId)' | jq '.template.spec.policyUpdateStrategy.type = "INPLACE_UPDATE"' > $TRIMMED_TEMPLATE_FILE
                    if [[ $OVERWRITE == true && $TEMPLATE_MISSING == false ]];then
                        echo "Updating template $TEMPLATE_NAME..."
                        OUTPUT=$(curl -ks -d @${TRIMMED_TEMPLATE_FILE} -H "Content-Type: application/json" -X PUT -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/policy/templates/${TEMPLATE_NAME}")
                    else
                        echo "Creating template $TEMPLATE_NAME..."
                        OUTPUT=$(curl -ks -d @${TRIMMED_TEMPLATE_FILE} -H "Content-Type: application/json" -X POST -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/policy/templates")
                    fi
                    if [[ $VERBOSE == true ]]; then
                        echo "$OUTPUT" | jq .
                    fi

                    # echo "See the template file (trimmed) at $TRIMMED_TEMPLATE_FILE that was sent to create the template."
                    rm $TRIMMED_TEMPLATE_FILE
                fi
            fi
        done
    fi

# Create the policy in the specified cluster group
if [[ $DRY_RUN == true ]]; then
    echo "The policy $POLICY_NAME would be created but the --dry-run option was specified."
else
    TRIMMED_POLICY_FILE=/tmp/policy_file_$$.json
    jq 'del(.policy.meta)' $POLICY_FILE | jq 'del(.policy.fullName.orgId)' > $TRIMMED_POLICY_FILE

    if [[ $POLICY_MISSING == true && $OVERWRITE == true ]]; then
        echo "Updating policy $POLICY_NAME..."
        OUTPUT=$(curl -ks -d @${TRIMMED_POLICY_FILE} -H "Content-Type: application/json" -X PUT -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies/${POLICY_NAME}")
    else
        echo "Creating policy $POLICY_NAME..."
        OUTPUT=$(curl -ks -d @${TRIMMED_POLICY_FILE} -H "Content-Type: application/json" -X POST -H "Authorization: Bearer ${CSP_ACCESS_TOKEN}" "${API_ENDPOINT}/v1alpha1/clustergroups/${CLUSTER_GROUP}/policies")
    fi

    if [[ $VERBOSE == true ]]; then
        echo "$OUTPUT" | jq .
    fi
    # echo "See the policy file (trimmed) at $TRIMMED_POLICY_FILE that was sent to create the policy."
    rm $TRIMMED_POLICY_FILE
fi
