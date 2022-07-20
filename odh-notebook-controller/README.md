# ODH Notebook Controller

The ODH Notebook Controller will watch the **Kubeflow Notebook** custom resource
events to extend the Kubeflow notebook controller behavior with the following
capabilities:

- Openshift ingress controller integration.
- Openshift OAuth sidecar injection.

![ODH Notebook Controller OAuth injection
diagram](./assets/odh-notebook-controller-oauth-diagram.png)

## Deployment

Add the following configuration to your `KfDef` object to install the
`odh-notebook-controller`:

```yaml
...
  - kustomizeConfig:
    repoRef:
      name: manifests
      path: odh-notebook-controller
    name: odh-notebook-controller
```

## Creating Notebooks

Create a notebook object with the image and other parameters such as the
environment variables, resource limits, tolerations, etc:

```shell
notebook_namespace=$(oc config view --minify -o jsonpath='{..namespace}')
cat <<EOF | oc apply -f -
---
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  name: thoth-minimal-oauth-notebook
  annotations:
    notebooks.opendatahub.io/inject-oauth: "true"
spec:
  template:
    spec:
      containers:
        - name: thoth-minimal-oauth-notebook
          image: quay.io/thoth-station/s2i-minimal-notebook:v0.3.0
          imagePullPolicy: Always
          workingDir: /opt/app-root/src
          env:
            - name: NOTEBOOK_ARGS
              value: |
                --ServerApp.port=8888
                --ServerApp.token=''
                --ServerApp.password=''
                --ServerApp.base_url=/notebook/${notebook_namespace}/thoth-minimal-oauth-notebook
          ports:
            - name: notebook-port
              containerPort: 8888
              protocol: TCP
          resources:
            requests:
              cpu: "1"
              memory: 1Gi
            limits:
              cpu: "1"
              memory: 1Gi
          livenessProbe:
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 1
            successThreshold: 1
            failureThreshold: 3
            httpGet:
              scheme: HTTP
              path: /notebook/${notebook_namespace}/thoth-minimal-oauth-notebook/api
              port: notebook-port
EOF
```

Open the notebook URL in your browser:

```shell
firefox "$(oc get route thoth-minimal-oauth-notebook -o jsonpath='{.spec.host}')/notebook/${notebook_namespace}/thoth-minimal-oauth-notebook"
```

Find more examples in the [notebook tests folder](../tests/resources/notebook-controller/).

## Notebook Culling

The notebook controller will scale to zero all the notebooks with last activity
older than the idle time. The controller will set the
`notebooks.kubeflow.org/last-activity` annotation when it detects a kernel with
activity.

To enable this feature, create a configmap with the culling configuration:

- **ENABLE_CULLING**: Enable culling feature (false by default).
- **IDLENESS_CHECK_PERIOD**: Polling frequency to update notebook last activity.
- **CULL_IDLE_TIME**: Maximum time to scale notebook to zero if no activity.

When the controller scales down the notebook pods, it will add the
`kubeflow-resource-stopped` annotation. Remove this annotation to start the
notebook server again.

For example, poll notebooks activity every 5 minutes and shutdown those that
have been in an idle state for more than 60 minutes:

```yaml
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: notebook-controller-culler-config
data:
  ENABLE_CULLING: "true"
  CULL_IDLE_TIME: "60" # In minutes (1 hour)
  IDLENESS_CHECK_PERIOD: "5" # In minutes
EOF
```

Restart the notebook controller deployment to refresh the configuration:

```shell
oc rollout restart deploy/notebook-controller-deployment
```

### Culling endpoint

The notebook controller [polls the
activity](https://github.com/kubeflow/kubeflow/blob/100657e8d1072136adf0a39315498b3d510c7c49/components/notebook-controller/pkg/culler/culler.go#L153-L155)
from a specific path:

```go
url := fmt.Sprintf(
    "http://%s.%s.svc.%s/notebook/%s/%s/api/kernels",
    nm, ns, domain, ns, nm)
```

Make sure the notebook is exposing the kernels at this path by configuring the
`base_url` parameter:

```shell
jupyter lab ... \
  --ServerApp.base_url=/notebook/${nb_namespace}/${nb_name}
```

## Notebook GPU

Install the [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) in
your cluster.

When the operator is installed, make sure it labeled the nodes in your cluster
with the number of GPUs available, for example:

```shell
$ oc get node ${GPU_NODE_NAME} -o yaml | grep "nvidia.com/gpu.count"
nvidia.com/gpu.count: "1"
```

In the notebook object, add the number of GPUs to use in the
`notebook.spec.template.spec.containers.resources` field:

```yaml
resources:
  requests:
    nvidia.com/gpu: "1"
  limits:
    nvidia.com/gpu: "1"
```

Allow the notebook to be scheduled in a GPU node by adding the following
toleration to the `notebook.spec.template.spec.tolerations` field:

```yaml
tolerations:
  - effect: NoSchedule
    key: nvidia.com/gpu
    operator: Exists
```

Finally, create the notebook and wait until it is scheduled in a GPU node.

## Updating Manifests

The upstream code must be adapted before being deployed with the Opendatahub
operator. This is done through two different scripts:

- Script `gen_kubeflow_manifests.sh` for the Kubeflow Notebook Controller.
- Script `gen_odh_manifests.sh` for the ODH Notebook Controller.

### Requirements

To update the notebook controller manifests, your environment must have the
following:

- [yq](https://github.com/mikefarah/yq#install) version 4.21.1+.
- [kustomize](https://sigs.k8s.io/kustomize/docs/INSTALL.md) version 3.2.0+

### Updating Kubeflow manifests

Use the `gen_kubeflow_manifests.sh` to update the Kubeflow Notebook Controller
manifests.

#### Variables

This script can be configured by modifying the following variables:

| **Name**        | **Description**                                     | **Example**                                      |
| --------------- | --------------------------------------------------- | ------------------------------------------------ |
| ctrl_dir        | Manifests output directory                          | kf-notebook-controller                           |
| ctrl_repository | Kubeflow upstream repository                        | github.com/opendatahub-io/kubeflow               |
| ctrl_branch     | Kubeflow repository branch to get cloned            | master                                           |
| ctrl_image      | Notebook controller container image                 | quay.io/opendatahub/kubeflow-notebook-controller |
| ctrl_tag        | Notebook controller container image tag             | latest                                           |
| ctrl_namespace  | Namespace where the notebook controller is deployed | opendatahub                                      |

#### Script

Run the script to update the Kubeflow Notebook Controller manifests:

```shell
./gen_kubeflow_manifests.sh
```

### Updating ODH manifests

Use the `gen_odh_manifests.sh` to update the ODH Notebook Controller manifests.

#### Variables

This script can be configured by modifying the following variables:

| **Name**        | **Description**                                     | **Example**                                 |
| --------------- | --------------------------------------------------- | ------------------------------------------- |
| ctrl_dir        | Manifests output directory                          | odh-notebook-controller                     |
| ctrl_repository | Kubeflow upstream repository                        | github.com/opendatahub-io/kubeflow          |
| ctrl_branch     | Kubeflow repository branch to get cloned            | master                                      |
| ctrl_image      | Notebook controller container image                 | quay.io/opendatahub/odh-notebook-controller |
| ctrl_tag        | Notebook controller container image tag             | latest                                      |
| ctrl_namespace  | Namespace where the notebook controller is deployed | opendatahub                                 |

#### Script

Run the script to update the ODH Notebook Controller manifests:

```shell
./gen_odh_manifests.sh
```
