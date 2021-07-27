# JupyterHub

JupyterHub comes with 2 components:

1. [jupyterhub](#jupyterhub)
2. [notebook-images](#notebook-images)

## jupyterhub

Contains deployment manifests for JupyterHub instance.

## Jupyterhub Architecture

Out of the box Jupyterhub will deploy its components in a High Availibility configuration. This entails 3 copies of the central Jupyterhub server as well as 3 copies of a Traefik Proxy that is reponsible for routing user traffic to notebook pods. To disable HA users can set the `replica` count for Jupyterhub and Traefik to `1`. In its current configuration, jupyterhub server pods will always have 1 leader pod. The other pods will stay on standby and constantly try and get a lock to become the new leader. In case you disable HA, there will always be just the one pod that is acting as the leader and the new pod that comes online in case of failure will become the new leader.  

### Parameters

JupyterHub component comes with 2 parameters exposed vie KFDef.

#### s3_endpoint_url

HTTP endpoint exposed by your S3 object storage solution which will be made available to JH users in `S3_ENDPOINT_URL` env variable.

#### storage_class

Name of the storage class to be used for PVCs created by JupyterHub component. This requires `storage-class` **overlay** to be enabled as well to work.

#### jupyterhub_groups_config

A ConfigMap containing comma separated lists of groups which would be used as Admin and User groups for JupyterHub. The default ConfgiMap can be found [here](jupyterhub/base/jupyterhub-groups-configmap.yaml).

#### jupyterhub_secret

A Secret containing configuration values like JupyterHub DB password or COOKIE_SECRET. The default Secret can be found [here](jupyterhub/base/jupyterhub-secret.yaml).

##### Examples

```
  - kustomizeConfig:
      overlays:
      - storage-class
      parameters:
        - name: storage_class
          value: standard
        - name: s3_endpoint_url
          value: "s3.odh.com"
      repoRef:
        name: manifests
        path: jupyterhub/jupyterhub
    name: jupyterhub
```

### Overlays

JupyterHub component comes with 3 overlays.

#### build

Contains build manifests for JupyterHub images.

#### storage-class

Customizes JupyterHub to use a specific `StorageClass` for PVCs, see `storage_class` parameter.

## Notebook Images

Contains manifests for Jupyter notebook images compatible with JupyterHub on OpenShift.

### Parameters

Notebook Images do not provide any parameters.

### Overlays

Notebook Images component comes with 3 overlays.

#### [additional](notebook-images/overlays/additional/)

Contains additional Jupyter notebook images.

#### [build](notebook-images/overlays/build/)

Contains build manifests for Jupyter notebook images.

#### [cuda](notebook-images/overlays/cuda/)

Contains build chain manifest for CUDA enabled ubi 7 based images, provides `tensorflow-gpu` enabled notebook image.

*NOTE:* Builds in this overlay require 4 GB of memory and 4 cpus

#### [cuda-11.0.3](notebook-images/overlays/cuda-11.0.3/)

Contains build chain manifest for CUDA 11.0.3 enabled ubi 8 based images with python 3.8 support, provides `tensorflow-gpu` and `pytorch-gpu` enabled notebook image.

*NOTE:* Builds in this overlay require 4-6 GB of memory

## Deploying JupyterHub notebooks to custom namespaces

JupyterHub has support for deploying notebooks to other namespaces. To help facilitate this, we provide a component under `jupyterhub/custom-notebook-deployment`. The steps to deploy are as follows:

1. Create the namespace for JupyterHub to reside in.
2. Create the namespace for the JupyterHub notebooks to reside in.
3. Create a kfdef in the jupyterhub namespace with at least the following Kustomize config in it (note how we are specifying the notebook destination under parameters)

    ```yaml
      - kustomizeConfig:
          overlays:
          - storage-class
          parameters:
            - name: storage_class
              value: standard
            - name: s3_endpoint_url
              value: "s3.odh.com"
            - name: notebook_destination
              value: <namespace from step 2>
          repoRef:
            name: manifests
            path: jupyterhub/jupyterhub
        name: jupyterhub
    ```

4. Create a kfdef in the jupyterhub notebook namespace with the following Kustomize config (note how we are specifying the jupyterhub namespace under parameters).

    ```yaml
        - kustomizeConfig:
          parameters:
            - name: jupyterhub_namespace
              value: <namespace from step 1>
            repoRef:
              name: manifests
              path: jupyterhub/custom-notebook-deployment
          name: jupyterhub-rbac
    ```
