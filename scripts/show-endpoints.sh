#!/usr/bin/env bash
# OpenEgiz — Show Kubernetes Service and Ingress endpoints for a Helm release.
set -euo pipefail

RELEASE_NAME="${RELEASE_NAME:-${1:-openegiz}}"
NAMESPACE="${NAMESPACE:-openegiz}"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}OpenEgiz — Kubernetes Endpoints (release=${RELEASE_NAME}, namespace=${NAMESPACE})${RESET}"
echo ""

# Ingress hosts (if enabled)
if kubectl get ingress -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE_NAME}" --no-headers 2>/dev/null | grep -q .; then
  tls_cfg="$(kubectl get ingress -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE_NAME}" -o jsonpath='{.items[0].spec.tls}' 2>/dev/null || true)"
  scheme="http"
  [ -n "$tls_cfg" ] && scheme="https"
  echo -e "${BOLD}Ingress:${RESET}"
  kubectl get ingress -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE_NAME}" \
    -o jsonpath='{range .items[*]}{range .spec.rules[*]}  {.host}{"\n"}{end}{end}' 2>/dev/null \
  | while read -r host; do
      [ -n "$host" ] && echo -e "  ${CYAN}${scheme}://${host}${RESET}"
    done
  echo ""
fi

printf "${DIM}%-38s %-12s %-28s${RESET}\n" "SERVICE" "TYPE" "ENDPOINT"
echo -e "${DIM}──────────────────────────────────────────────────────────────────────────────${RESET}"

kubectl get svc -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE_NAME}" --no-headers \
  -o custom-columns='NAME:.metadata.name,TYPE:.spec.type,IP:.spec.clusterIP,PORT:.spec.ports[0].port,NODEPORT:.spec.ports[0].nodePort' 2>/dev/null \
| while read -r name type ip port nodeport; do
    if [ "$type" = "NodePort" ] && [ "$nodeport" != "<none>" ]; then
      printf "  %-36s ${GREEN}%-12s${RESET} ${CYAN}http://%s:%s${RESET}\n" "$name" "$type" "$NODE_IP" "$nodeport"
    elif [ "$ip" = "None" ]; then
      printf "  ${DIM}%-36s %-12s headless:%s${RESET}\n" "$name" "$type" "$port"
    else
      printf "  ${YELLOW}%-36s${RESET} %-12s %s:%s\n" "$name" "$type" "$ip" "$port"
    fi
done

echo ""
