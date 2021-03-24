IMAGE=odh-manifests-test
GIT_ORG=opendatahub-io
GIT_BRANCH=master
ODHPROJECT=opendatahub
OPENSHIFT_USER=
OPENSHIFT_PASS=
OPENSHIFT_LOGIN_PROVIDER=
# Setting SKIP_INSTALL will let you run the tests against an ODH instance that is already setup
SKIP_INSTALL=

# SKIP_OPERATOR_INSTALL, SKIP_KFDEF_INSTALL will be skipped by setting true for SKIL_INSTALL.
# However, if you set the first 2 variables to true then the openshift identifier will be configured.
# Ex)SKIP_INSTALL= , SKIP_OPERATOR_INSTALL=True, SKIP_KFDEF_INSTALL=True

# Setting SKIP_OPERATOR_INSTALL will let you skip deploying ODH Operater.This will enable more delicate manipulation.
SKIP_OPERATOR_INSTALL=

# Setting SKIP_KFDEF_INSTALL will let you skip creating Kfdef CR. This will enable more delicate manipulation.
SKIP_KFDEF_INSTALL=

# Setting TESTS_REGEX will allow you to change which tests are going to be run
TESTS_REGEX=
# Location inside the container where CI system will retrieve files after a test run
ARTIFACT_DIR=/tmp/artifacts
LOCAL_ARTIFACT_DIR="${PWD}/artifacts"

# Setting this for pusing ODH Manifests Test Image to quay.io for ODS Operator Test Harness
DEFAULT_IMAGE_REGISTRY=quay.io
DEFAULT_REGISTRY_NAMESPACE=modh
DEFAULT_IMAGE_TAG=latest

# Do not change
IMAGE_REGISTRY ?=$(DEFAULT_IMAGE_REGISTRY)
REGISTRY_NAMESPACE ?=$(DEFAULT_REGISTRY_NAMESPACE)
IMAGE_TAG ?=$(DEFAULT_IMAGE_TAG)
ODH_MANIFEST_TEST_FULL_IMAGE_NAME=$(IMAGE_REGISTRY)/$(REGISTRY_NAMESPACE)/$(IMAGE):$(IMAGE_TAG)

all: test
test: build run clean

build:
	@echo "Building the $(IMAGE)"
	podman build -t $(ODH_MANIFEST_TEST_FULL_IMAGE_NAME) --build-arg ORG=$(GIT_ORG) --build-arg BRANCH=$(GIT_BRANCH) -f $(shell pwd)/Dockerfile .
run:
	# Confirm that we have a directory for storing any screenshots from selenium tests
	mkdir -p ${LOCAL_ARTIFACT_DIR}/screenshots
	oc config view --flatten --minify > /tmp/tests-kubeconfig
        # Add --privileged because someone does not use rootless podman. With this option, you can attach host volume to container.
	podman run  --privileged -e SKIP_INSTALL=$(SKIP_INSTALL) -e TESTS_REGEX=$(TESTS_REGEX) -e ODHPROJECT=$(ODHPROJECT) \
		-e OPENSHIFT_USER="$(OPENSHIFT_USER)" -e OPENSHIFT_PASS="$(OPENSHIFT_PASS)" -e OPENSHIFT_LOGIN_PROVIDER=$(OPENSHIFT_LOGIN_PROVIDER) -e ARTIFACT_DIR=$(ARTIFACT_DIR) \
		-e SKIP_OPERATOR_INSTALL="${SKIP_OPERATOR_INSTALL}" -e SKIP_KFDEF_INSTALL="${SKIP_KFDEF_INSTALL}" \
		-it -v ${LOCAL_ARTIFACT_DIR}/:$(ARTIFACT_DIR):z -v /tmp/tests-kubeconfig:/tmp/kubeconfig:z $(ODH_MANIFEST_TEST_FULL_IMAGE_NAME)

clean:
	oc delete -n $(ODHPROJECT) kfdef opendatahub || true
	oc delete project $(ODHPROJECT) || echo -e "\n\n==> If the project deletion failed, you can try to use this script to force it: https://raw.githubusercontent.com/jefferyb/useful-scripts/master/openshift/force-delete-openshift-project\n\n"
	#Clean up openshift-operators namespace
	oc get csv -n openshift-operators -o name | grep strimzi-cluster-operator | xargs oc delete -n openshift-operators || true
	oc get csv -n openshift-operators -o name | grep opendatahub-operator | xargs oc delete -n openshift-operators || true
	oc delete subscription -n openshift-operators -l peak.test.subscription=opendatahub-operator
	oc get mutatingwebhookconfiguration -o name | grep seldon | grep $(ODHPROJECT) | xargs oc delete || true
	oc get mutatingwebhookconfiguration -o name | grep katib | grep $(ODHPROJECT) | xargs oc delete || true
	oc get validatingwebhookconfiguration -o name | grep seldon | grep $(ODHPROJECT) | xargs oc delete || true
	oc get validatingwebhookconfiguration -o name | grep katib | grep $(ODHPROJECT) | xargs oc delete || true

push-image:
	@echo "Pushing the $(ODH_MANIFEST_TEST_FULL_IMAGE_NAME) image to $(IMAGE_REGISTRY)/$(REGISTRY_NAMESPACE)"
	podman push $(ODH_MANIFEST_TEST_FULL_IMAGE_NAME)

image: build push-image

# During building ODH manifest test image, many garbage iamges will be created. This target clean them up.
clean-images:
	for im in $$(podman images|grep '\<none' |awk '{print $$3}'); do podman rmi --force $$im;done
