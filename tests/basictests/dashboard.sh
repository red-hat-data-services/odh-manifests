#!/bin/bash

source $TEST_DIR/common

MY_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)

source ${MY_DIR}/../util

os::test::junit::declare_suite_start "$MY_SCRIPT"

function check_resources() {
    header "Testing dashboard installation"
    os::cmd::expect_success "oc project ${ODHPROJECT}"
    os::cmd::try_until_text "oc get rhods-dashboard rhods-dashboard" "rhods-dashboard" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get role rhods-dashboard" "rhods-dashboard" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get rolebinding rhods-dashboard" "rhods-dashboard" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get route rhods-dashboard" "rhods-dashboard" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get service rhods-dashboard" "rhods-dashboard" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get deployment rhods-dashboard" "rhods-dashboard" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get pods -l deployment=rhods-dashboard --field-selector='status.phase=Running' -o jsonpath='{$.items[*].metadata.name}' | wc -w" "2" $odhdefaulttimeout $odhdefaultinterval
}

function check_ui() {
    header "Testing dashboard UI loads"
    os::cmd::expect_success "oc project ${ODHPROJECT}"
    local route="https://"$(oc get route rhods-dashboard -o jsonpath='{.spec.host}')
    os::log::info "$route"
    os::cmd::try_until_text "curl -k -s -o /dev/null -w \"%{http_code}\" $route/api/components" "200" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "curl -k $route/api/components | jq '.[].key'" "jupyterhub" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "curl -k $route" "<title>Open Data Hub Dashboard</title>" $odhdefaulttimeout $odhdefaultinterval
}

check_resources
check_ui

os::test::junit::declare_suite_end
