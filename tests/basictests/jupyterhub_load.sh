#!/bin/bash

source $TEST_DIR/common

MY_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)

source ${MY_DIR}/../util

JH_LOGIN_USER=${OPENSHIFT_USER:-"admin"} #Username used to login to JH
JH_LOGIN_PASS=${OPENSHIFT_PASS:-"admin"} #Password used to login to JH
OPENSHIFT_LOGIN_PROVIDER=${OPENSHIFT_LOGIN_PROVIDER:-"htpasswd-provider"} #OpenShift OAuth provider used for login
JH_AS_ADMIN=${JH_AS_ADMIN:-"true"} #Expect the user to be Admin in JupyterHub
PUSHGATEWAY_URL=${PUSHGATEWAY_URL:-"localhost:9091"} #Expect psi pushgateway url to put load test result data.

JUPYTER_IMAGES=(s2i-tensorflow-notebook:v0.0.2)

JUPYTER_NOTEBOOK_DIRS=(tensorflow pytorch)
JUPYTER_NOTEBOOK_FILES=(TensorFlow-MNIST-Minimal.ipynb PyTorch-MNIST-Minimal.ipynb)

JH_AS_ADMIN=false
JH_NOTEBOOK_SIZE=${JH_NOTEBOOK_SIZE:-"Small"}

os::test::junit::declare_suite_start "$MY_SCRIPT"

function test_jupyterhub() {
    header "Testing JupyterHub installation"
    os::cmd::expect_success "oc project ${ODHPROJECT}"
    os::cmd::try_until_text "oc get deploymentconfig jupyterhub" "jupyterhub" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get deploymentconfig jupyterhub-db" "jupyterhub-db" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get pods -l deploymentconfig=jupyterhub --field-selector='status.phase=Running' -o jsonpath='{$.items[*].metadata.name}'" "jupyterhub" $odhdefaulttimeout $odhdefaultinterval
    runningpods=($(oc get pods -l deploymentconfig=jupyterhub --field-selector="status.phase=Running" -o jsonpath="{$.items[*].metadata.name}"))
    os::cmd::expect_success_and_text "echo ${#runningpods[@]}" "1"
    os::cmd::try_until_text "oc get pods -l deploymentconfig=jupyterhub-db --field-selector='status.phase=Running' -o jsonpath='{$.items[*].metadata.name}'" "jupyterhub-db" $odhdefaulttimeout $odhdefaultinterval
    runningpods=($(oc get pods -l deploymentconfig=jupyterhub-db --field-selector="status.phase=Running" -o jsonpath="{$.items[*].metadata.name}"))
    os::cmd::expect_success_and_text "echo ${#runningpods[@]}" "1"
}

function test_start_notebook() {
    local notebook_name=$1
    local user=$2
    shift 2
    local notebook_files=$@
    local size=${JH_NOTEBOOK_SIZE}

    header "Testing Jupyter Notebook ${notebook_name} Execution (Size: ${size})"
    os::cmd::expect_success "oc project ${ODHPROJECT}"
    route="https://"$(oc get route jupyterhub -o jsonpath='{.spec.host}' -n ${ODHPROJECT})
    os::cmd::expect_success "JH_HEADLESS=true JH_USER_NAME=${user} JH_LOGIN_USER=${JH_LOGIN_USER} JH_LOGIN_PASS=${JH_LOGIN_PASS} OPENSHIFT_LOGIN_PROVIDER=${OPENSHIFT_LOGIN_PROVIDER} \
    JH_NOTEBOOKS=${notebook_files} JH_NOTEBOOK_IMAGE=${notebook_name} JH_AS_ADMIN=${JH_AS_ADMIN} \
    JH_URL=${route} JH_NOTEBOOK_SIZE=${size} PUSHGATEWAY_URL=${PUSHGATEWAY_URL}\
    python3 ${MY_DIR}/jupyterhub/jhtest_load.py"

}

function test_notebooks() {
    notebooks=()
    for index in ${!JUPYTER_NOTEBOOK_FILES[*]}; do
        notebooks+=(notebook-benchmarks/${JUPYTER_NOTEBOOK_DIRS[$index]}/${JUPYTER_NOTEBOOK_FILES[$index]})
    done
   
    echo "NOTEBOOKS: ${notebooks[@]}" 
    test_start_notebook ${JUPYTER_IMAGES[0]}  jh-test0 $(IFS=, ; echo "${notebooks[*]}")
}

test_jupyterhub
test_notebooks

os::test::junit::declare_suite_end
