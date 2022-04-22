#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail
set -x

export KUBECONFIG=${SHARED_DIR}/kubeconfig

AZURE_AUTH_LOCATION="${CLUSTER_PROFILE_DIR}/osServicePrincipal.json"
AZURE_AUTH_CLIENT_ID="$(<"${AZURE_AUTH_LOCATION}" jq -r .clientId)"
AZURE_AUTH_CLIENT_SECRET="$(<"${AZURE_AUTH_LOCATION}" jq -r .clientSecret)"
AZURE_AUTH_TENANT_ID="$(<"${AZURE_AUTH_LOCATION}" jq -r .tenantId)"

# log in with az
az login --service-principal -u "${AZURE_AUTH_CLIENT_ID}" -p "${AZURE_AUTH_CLIENT_SECRET}" --tenant "${AZURE_AUTH_TENANT_ID}" --output none

AZURE_REGION="$(oc get -o jsonpath='{.status.platformStatus.aws.region}' infrastructure cluster)"
export AZURE_REGION

export SSH_PRIV_KEY_PATH=${CLUSTER_PROFILE_DIR}/ssh-privatekey
export PULL_SECRET_PATH=${CLUSTER_PROFILE_DIR}/pull-secret

echo "PLATFORM_VERSION: '${PLATFORM_VERSION}'"

set -x
infra_id=$(oc get -o jsonpath='{.status.infrastructureName}{"\n"}' infrastructure cluster)

# Get the RHEL image URL
RHEL_IMAGE_URL=$(az vm image show --urn RedHat:RHEL:${RHEL_IMAGE_SKU}:${RHEL_IMAGE} --query 'id')

#Start to provision rhel instances from template
for count in $(seq 1 ${RHEL_WORKER_COUNT}); do
  echo "$(date -u --rfc-3339=seconds) - Provision ${infra_id}-rhel-${count} ..."
  # az command to configure RHEL VM's
  az vm create --resource-group "${infra_id}-rg" \
    --name "${infra_id}-rhel-${count}" \
    --image "${RHEL_IMAGE_URL}"
    --specialized
  
  loop=10
  while [ ${loop} -gt 0 ]; do
    # az command to get VM IP's
    rhel_node_ip=$(az vm list ip-addresses -g "${infra_id}-rg" --name "${infra_id}-rhel-${count}")
    if [ "x${rhel_node_ip}" == "x" ]; then
      loop=$(( loop - 1 ))
      sleep 30
    else
      break
    fi
  done
  if [ "x${rhel_node_ip}" == "x" ]; then
    echo "Unable to get ip of rhel instance ${infra_id}-rhel-${count}!"
    exit 1
  fi

  echo ${rhel_node_ip} >> /tmp/rhel_nodes_ip
done

cp /tmp/rhel_nodes_ip "${ARTIFACT_DIR}"
