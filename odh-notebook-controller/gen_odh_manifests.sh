#!/bin/bash
set -eu -o pipefail

ctrl_dir="odh-notebook-controller"
ctrl_repository="github.com/opendatahub-io/kubeflow"
ctrl_branch="master"
ctrl_image="quay.io/opendatahub/odh-notebook-controller"
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
ctrl_controller_dir=${tmp_dir}/components/odh-notebook-controller
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

echo -n "   .. Updating controller image"
sed -i 's,newName:.*,newName: '${ctrl_image}',g' ${ctrl_dir}/base/kustomization.yaml
sed -i 's,newTag:.*,newTag: '${ctrl_tag}',g' ${ctrl_dir}/base/kustomization.yaml
echo -e "\r    ✓"

echo -n ".. Copying controller/default folder"
cp -r "${ctrl_controller_dir}/config/default" ${ctrl_dir}/default
echo -e "\r ✓"

echo -n "   .. Updating controller namespace to opendatahub"
sed -i 's,namespace:.*,namespace: '${ctrl_namespace}',g' ${ctrl_dir}/default/kustomization.yaml
echo -e "\r    ✓"

echo -n ".. Copying RBAC folder"
cp -r "${ctrl_controller_dir}/config/rbac" ${ctrl_dir}/rbac
echo -e "\r ✓"

echo -n ".. Copying manager deployment folder"
cp -r "${ctrl_controller_dir}/config/manager" ${ctrl_dir}/manager
echo -e "\r ✓"

echo -n ".. Copying mutating webhook folder"
cp -r "${ctrl_controller_dir}/config/webhook" ${ctrl_dir}/webhook
echo -e "\r ✓"

echo -n ".. Removing unused files"
rm -f \
    ${ctrl_dir}/rbac/leader_election_role_binding.yaml \
    ${ctrl_dir}/rbac/leader_election_role.yaml
echo -e "\r ✓"
