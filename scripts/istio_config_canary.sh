#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/config_istio_canary.sh) and 'source' it from your pipeline job
#    source ./scripts/config_istio_canary.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/config_istio_canary.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/config_istio_canary.sh

# Configure Istio gateway with a destination rule (stable/canary), and virtual service

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

#Check namespace availability
echo "=========================================================="
echo "CHECKING CLUSTER readiness and namespace existence"
if kubectl get namespace ${CLUSTER_NAMESPACE}; then
  echo -e "Namespace ${CLUSTER_NAMESPACE} found."
else
  kubectl create namespace ${CLUSTER_NAMESPACE}
  echo -e "Namespace ${CLUSTER_NAMESPACE} created."
fi

echo "=========================================================="
echo "CHECK SIDECAR is automatically injected"
AUTO_SIDECAR_INJECTION=$(kubectl get namespace ${CLUSTER_NAMESPACE} -o json | jq -r '.metadata.labels."istio-injection"')
if [ "${AUTO_SIDECAR_INJECTION}" == "enabled" ]; then
    echo "Automatic Istio sidecar injection already enabled"
else
    # https://istio.io/docs/setup/kubernetes/sidecar-injection/#automatic-sidecar-injection
    kubectl label namespace ${CLUSTER_NAMESPACE} istio-injection=enabled
    echo "Automatic Istio sidecar injection now enabled"
    kubectl get namespace ${CLUSTER_NAMESPACE} -L istio-injection
fi

echo "=========================================================="
echo "CHECK GATEWAY is configured"
if kubectl get gateway gateway-${IMAGE_NAME} --namespace ${CLUSTER_NAMESPACE}; then
  echo -e "Istio gateway found: gateway-${IMAGE_NAME}"
  kubectl get gateway gateway-${IMAGE_NAME} --namespace ${CLUSTER_NAMESPACE} -o yaml
else
  if [ -z "${GATEWAY_FILE}" ]; then GATEWAY_FILE=istio_gateway.yaml ; fi
  if [ ! -f ${GATEWAY_FILE} ]; then
    cat > ${GATEWAY_FILE} << EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: gateway-${IMAGE_NAME}
spec:
  selector:
    istio: ingressgateway # use istio default controller
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: virtual-service-${IMAGE_NAME}
spec:
  hosts:
    - '*'
  gateways:
    - gateway-${IMAGE_NAME}
  http:
    - route:
        - destination:
            host: ${IMAGE_NAME}
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: destination-rule-${IMAGE_NAME}
spec:
  host: ${IMAGE_NAME}
  subsets:
  - name: stable
    labels:
      version: 'stable'
  - name: canary
    labels:
      version: 'canary'
EOF
    #sed -e "s/\${IMAGE_NAME}/${IMAGE_NAME}/g" ${GATEWAY_FILE}
  fi
  cat ${GATEWAY_FILE}
  kubectl apply -f ${GATEWAY_FILE} --namespace ${CLUSTER_NAMESPACE}
fi

kubectl get gateways,destinationrules,virtualservices --namespace ${CLUSTER_NAMESPACE}