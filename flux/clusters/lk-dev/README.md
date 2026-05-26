# lk-dev cluster

Reference env for the Flux GitOps spike. Configured for the existing
`dcapi-controlplane-rke2` cluster on the WSO2 LK Harvester dev
environment.

## Hostnames

- Rancher: `rancher-lk-dev.wso2.com`
- dc-api ingress: `dcapi.lk-dev.internal.wso2.com`
- cloud-ui ingress: `cloud.lk-dev.internal.wso2.com`

## Image source

`ghcr.io/hiranadikari/dc-api` (the fork's image stream from the
sovereign-cloud monorepo's CI).
