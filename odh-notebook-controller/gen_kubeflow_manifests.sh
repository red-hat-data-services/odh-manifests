#!/bin/bash
set -eu -o pipefail

ctrl_dir="kf-notebook-controller"
ctrl_repository="github.com/opendatahub-io/kubeflow"
ctrl_branch="master"
ctrl_image="quay.io/opendatahub/kubeflow-notebook-controller"
ctrl_tag="master-bd77bfc"
ctrl_namespace="opendatahub"

cleanup() {
    echo -n ".. Removing the temporary clone"
    rm -rf ${tmp_dir}
    echo -e "\r ✓ "
}

trap cleanup EXIT

echo -n ".. Temporarily cloning the upstream repo"
tmp_dir=$(mktemp -d)
ctrl_controller_dir=${tmp_dir}/components/notebook-controller
git clone \
    -c advice.detachedHead=false --quiet --depth 1 \
    --branch ${ctrl_branch} --single-branch \
    https://${ctrl_repository}.git  ${tmp_dir} > /dev/null
echo -e "\r ✓"

echo -n ".. Reinitializing the controller folder structure"
rm -rf ${ctrl_dir}
mkdir ${ctrl_dir}
echo -e "\r ✓"

echo -n ".. Copying controller/base folder"
cp -r "${ctrl_controller_dir}/config/base" ${ctrl_dir}/base
echo -e "\r ✓"

echo -n ".. Copying controller/default folder"
cp -r "${ctrl_controller_dir}/config/default" ${ctrl_dir}/default
echo -e "\r ✓"

echo -n ".. Copying controller/overlays folder"
mkdir ${ctrl_dir}/overlays
cp -r "${ctrl_controller_dir}/config/overlays/openshift" ${ctrl_dir}/overlays/openshift
echo -e "\r ✓"

echo -n "   .. Updating controller namespace to opendatahub"
sed -i 's,namespace:.*,namespace: '${ctrl_namespace}',g' ${ctrl_dir}/overlays/openshift/kustomization.yaml
echo -e "\r    ✓"

echo -n "   .. Updating controller image"
sed -i 's,newName:.*,newName: '${ctrl_image}',g' ${ctrl_dir}/overlays/openshift/kustomization.yaml
sed -i 's,newTag:.*,newTag: '${ctrl_tag}',g' ${ctrl_dir}/overlays/openshift/kustomization.yaml
echo -e "\r    ✓"

echo -n ".. Copying CRDs folder"
cp -r "${ctrl_controller_dir}/config/crd" ${ctrl_dir}/crd
echo -e "\r ✓"

echo -n ".. Copying RBAC folder"
cp -r "${ctrl_controller_dir}/config/rbac" ${ctrl_dir}/rbac
echo -e "\r ✓"

echo -n "   .. Disable leader election RBAC"
sed -i 's,^\- leader_election_role.*,#&,' ${ctrl_dir}/rbac/kustomization.yaml
echo -e "\r    ✓"

echo -n ".. Copying manager deployment folder"
cp -r "${ctrl_controller_dir}/config/manager" ${ctrl_dir}/manager
echo -e "\r ✓"

echo -n "   .. Disabling kustomize NameSuffixHash property"
yq -i '.generatorOptions.disableNameSuffixHash = true' ${ctrl_dir}/manager/kustomization.yaml
echo -e "\r    ✓"

echo -n ".. Removing unused files"
rm -f \
    ${ctrl_dir}/default/manager_auth_proxy_patch.yaml \
    ${ctrl_dir}/default/manager_image_patch.yaml \
    ${ctrl_dir}/default/manager_prometheus_metrics_patch.yaml \
    ${ctrl_dir}/default/manager_webhook_patch.yaml \
    ${ctrl_dir}/default/webhookcainjection_patch.yaml \
    ${ctrl_dir}/rbac/auth_proxy_role_binding.yaml \
    ${ctrl_dir}/rbac/auth_proxy_role.yaml \
    ${ctrl_dir}/rbac/auth_proxy_service.yaml \
    ${ctrl_dir}/rbac/leader_election_role_binding.yaml \
    ${ctrl_dir}/rbac/leader_election_role.yaml
echo -e "\r ✓"
