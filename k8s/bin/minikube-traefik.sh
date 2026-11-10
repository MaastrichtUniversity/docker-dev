#!/usr/bin/env bash
# Install Traefik with the Gateway API provider on a local minikube
# cluster, so the dev overlay's Gateway/HTTPRoute objects route traffic
# the same way they do on k3s (tst/acc/prd). Prints the /etc/hosts block
# for the 13 dev public hosts at the end.
#
# Usage:  k8s/bin/minikube-traefik.sh
#
# Prereqs: minikube + kubectl pointed at a RUNNING minikube cluster
# (docker driver recommended), internet access to github.com (the script
# pulls the Gateway API CRDs and Traefik's official Gateway API RBAC).
#
# What it does (all idempotent, re-runnable):
#   1. minikube addons enable loadbalancer   (metallb: gives the
#      LoadBalancer Service an external IP)
#   2. Gateway API CRDs, standard channel (pinned version below)
#   3. Traefik's official Gateway API RBAC + its ServiceAccount
#      (Service in 'default' - matches the official RBAC binding)
#   4. traefik Deployment + LoadBalancer Service on :80/:443.
#      Traefik creates the GatewayClass named 'traefik' itself, which is
#      what the dev gateway.yaml's gatewayClassName references.
#
# The dev Gateway objects are HTTP-only, so :443 is a placeholder until
# an https listener is added for local TLS work.
set -euo pipefail

GATEWAY_API_VER=v1.7.0
TRAEFIK_DOC_TAG=v3.7   # docs/manifest branch for the 3.7 line (official URL)
TRAEFIK_IMAGE=traefik:v3.7
NS=default

ctx=$(kubectl config current-context 2>/dev/null || true)
expected_context=${MINIKUBE_PROFILE:-minikube}
if [ "$ctx" != "$expected_context" ]; then
  echo "kubectl context is '$ctx', expected minikube profile context '$expected_context'; refusing to mutate a cluster." >&2
  exit 1
fi

echo "==> 1/4 loadbalancer addon (metallb)"
if minikube addons enable loadbalancer 2>/dev/null; then
  echo "    enabled"
else
  echo "    NOT available on this minikube driver - the traefik Service" >&2
  echo "    will stay Pending; use 'minikube tunnel' (see README) or the" >&2
  echo "    docker driver instead." >&2
fi

echo "==> 2/4 Gateway API CRDs ($GATEWAY_API_VER, standard channel)"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VER}/standard-install.yaml"

echo "==> 3/4 Traefik Gateway API RBAC + ServiceAccount"
kubectl apply -f "https://raw.githubusercontent.com/traefik/traefik/${TRAEFIK_DOC_TAG}/docs/content/reference/dynamic-configuration/kubernetes-gateway-rbac.yml"
kubectl create serviceaccount -n "$NS" traefik-controller --dry-run=client -o yaml | kubectl apply -f -

echo "==> 4/4 Traefik Deployment + Service"
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik
  namespace: ${NS}
  labels:
    app.kubernetes.io/name: traefik
    app.kubernetes.io/part-of: datahub-dev-infra
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: traefik
  template:
    metadata:
      labels:
        app.kubernetes.io/name: traefik
    spec:
      serviceAccountName: traefik-controller
      containers:
        - name: traefik
          image: ${TRAEFIK_IMAGE}
          args:
            # dev only needs the Gateway API provider (the overlay has no
            # Ingress or IngressRoute objects).
            - --providers.kubernetesgateway=true
            - --entrypoints.web.address=:80
            - --entrypoints.websecure.address=:443
          ports:
            - name: web
              containerPort: 80
            - name: websecure
              containerPort: 443
          securityContext:
            readOnlyRootFilesystem: true
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: traefik
  namespace: ${NS}
  labels:
    app.kubernetes.io/name: traefik
    app.kubernetes.io/part-of: datahub-dev-infra
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: traefik
  ports:
    - name: web
      port: 80
      targetPort: 80
    - name: websecure
      port: 443
      targetPort: 443
EOF

echo "==> waiting for traefik to be ready"
kubectl -n "$NS" rollout status deploy/traefik --timeout=180s

LB_IP=$(kubectl -n "$NS" get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
for _ in $(seq 1 30); do
  [ -n "$LB_IP" ] && break
  sleep 2
  LB_IP=$(kubectl -n "$NS" get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
done

if [ -z "$LB_IP" ]; then
  cat >&2 <<'EOR'
Traefik is running, but no LoadBalancer IP appeared yet.
Options:
  - re-check:  kubectl -n default get svc traefik
  - docker driver: make sure 'minikube addons enable loadbalancer' worked
  - other drivers / 127.0.0.1: run 'minikube tunnel' (needs sudo) and use
    127.0.0.1 below
EOR
  LB_IP=127.0.0.1
fi

echo
echo "==> Traefik is up. Add these lines to /etc/hosts, e.g.:"
echo
echo "    sudo tee -a /etc/hosts <<'EOF'"
# Keep in sync with the listener hostnames in k8s/overlays/dev/gateway.yaml
for host in \
  app.mdr.dev.dh.unimaas.nl \
  elastic.dev.dh.unimaas.nl \
  download.dev.dh.unimaas.nl \
  upload.dev.dh.unimaas.nl \
  mdr.dev.dh.unimaas.nl \
  epicpid.dev.dh.unimaas.nl \
  help.mdr.dev.dh.unimaas.nl \
  helpbackend.dev.dh.unimaas.nl \
  dev.dh.unimaas.nl \
  keycloak.dev.dh.unimaas.nl \
  auth.dev.dh.unimaas.nl \
  admin.dev.dh.unimaas.nl \
  admintoolsbackend.dev.dh.unimaas.nl
do
  echo "    ${LB_IP} ${host}"
done
echo "    EOF"
echo
echo "Then verify, e.g.:  curl -s http://mdr.dev.dh.unimaas.nl/ | head"
