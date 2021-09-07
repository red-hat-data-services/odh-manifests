# OSD Configs

A simple Kustomize App that provides utilities for running RHODS on OpenShift Dedicated

# Installation
To install the OpenShift Dedicated-specific configs add the following to the `KfDef` in your yaml file.

```
  - kustomizeConfig:
      repoRef:
        name: manifests
        path: osd-configs
    name: osd-configs
```
