#!/bin/bash
export OCP_RELEASE="4.8.46-x86_64"
#export LOCAL_REGISTRY="aosratp.azurecr.io"
export LOCAL_REGISTRY="10.21.196.29:5000"
export LOCAL_REPOSITORY="ocp4/openshift4"
export PRODUCT_REPO='openshift-release-dev'
export LOCAL_SECRET_JSON='pull-secret'
export RELEASE_NAME="ocp-release"

/tmp/oc adm -a ${LOCAL_SECRET_JSON} release mirror \
   --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE} \
   --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
   --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE} \
   --insecure-skip-tls-verify=true

/tmp/oc adm release extract -a ${LOCAL_SECRET_JSON} --command=openshift-install "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}"