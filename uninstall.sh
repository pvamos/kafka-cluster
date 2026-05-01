#!/usr/bin/env bash
#set -euo pipefail
set -e

# =============================================================================
# uninstall.sh
#
# Removes everything installed by install.sh, in a safe order.
#
# What this script does:
#   - Uninstalls EMQX (HostPort) and the EMQX->Kafka bridge Job
#   - Uninstalls Traefik dashboard ingress, Headlamp, Longhorn UI ingress
#   - Uninstalls Kafka UI, the Strimzi-managed Kafka cluster, Strimzi operator
#   - Uninstalls the Kafka local-storage Helm release (PVs chart)
#
# Defaults are SAFE:
#   - Namespaces are kept (PURGE_NS=false) so you can inspect leftovers.
#   - PVs are kept (DELETE_PVS=false). The PVs created by kafka-local-storage
#     use reclaimPolicy=Retain, so they persist unless you explicitly delete them.
#
# You can override behavior with environment variables:
#   PURGE_NS=true      -> also delete the kafka, emqx, and headlamp namespaces
#   DELETE_PVS=true    -> also delete the local PV objects (control/worker PVs)
#
# Examples:
#   PURGE_NS=true ./uninstall.sh
#   PURGE_NS=true DELETE_PVS=true ./uninstall.sh
# =============================================================================

# ------------- Config (keep in sync with install.sh) -------------------------
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
KAFKA_NS="$(yq e -r '.namespace' "${SCRIPTDIR}/kafka/values.yaml")"
HEADLAMP_NS="$(yq e -r '.namespace' "${SCRIPTDIR}/headlamp/values.yaml")"
LONGHORN_NS="$(yq e -r '.namespace' "${SCRIPTDIR}/longhorn-ui/values.yaml")"
TRAEFIK_NS="$(yq e -r '.namespace' "${SCRIPTDIR}/traefik-dashboard/values.yaml")"
VERNEMQ_NS="$(yq e '.namespace' "${SCRIPTDIR}/vernemq/values.yaml")"
CLICKHOUSE_NS="clickhouse"
GRAFANA_NS="$(yq e '.namespace' "${SCRIPTDIR}/grafana/values.yaml")"

KAFKA_CLUSTER_NAME="$(yq e -r '.kafka.clusterName' "${SCRIPTDIR}/kafka/values.yaml")"

# PV names expected from kafka-local-storage chart (adjust to your nodes)
CTRL_PVS=($(yq e -r '.controllerPersistentVolumes[].name' "${SCRIPTDIR}/kafka-local-storage/values.yaml" | xargs))
BROKER_PVS=($(yq e -r '.brokerPersistentVolumes[].name'     "${SCRIPTDIR}/kafka-local-storage/values.yaml" | xargs))

# Controls (safe defaults)
#PURGE_NS="${PURGE_NS:-false}"                   # delete namespaces too?
#DELETE_PVS="${DELETE_PVS:-false}"               # delete PV objects too?
#DEL_VAR_LIB_KAFKA="${DEL_VAR_LIB_KAFKA:-false}" # delete /var/lib/kafka/* on nodes too?
PURGE_NS="true"          # delete namespaces too?
DELETE_PVS="true"        # delete PV objects too?
DEL_VAR_LIB_KAFKA="true" # delete /var/lib/kafka/* on nodes too?
DELETE_CLICKHOUSE_CRDS="true"

# ------------- Helpers -------------------------------------------------------
hr() { echo '------------------------------'; }

helm_uninstall() {
  local ns="$1" rel="$2"
  if helm -n "$ns" status "$rel" >/dev/null 2>&1; then
    echo "Uninstalling Helm release: $rel (ns=$ns)"
    helm -n "$ns" uninstall "$rel" || true
  else
    echo "Skipping Helm release (not installed): $rel (ns=$ns)"
  fi
}

delete_strimzi_crs() {
  local ns="$1"
  # Best-effort: delete all Strimzi CRs that commonly block the namespace
  kubectl -n "$ns" delete kafkabridges.kafka.strimzi.io --all --ignore-not-found --wait=false || true
  kubectl -n "$ns" delete kafkaconnectors.kafka.strimzi.io --all --ignore-not-found --wait=false || true
  kubectl -n "$ns" delete kafkaconnects.kafka.strimzi.io --all --ignore-not-found --wait=false || true
  kubectl -n "$ns" delete kafkamirrormaker2s.kafka.strimzi.io --all --ignore-not-found --wait=false || true
  kubectl -n "$ns" delete kafkarebalances.kafka.strimzi.io --all --ignore-not-found --wait=false || true
  kubectl -n "$ns" delete kafkanodepools.kafka.strimzi.io --all --ignore-not-found --wait=false || true
  kubectl -n "$ns" delete kafkatopics.kafka.strimzi.io --all --ignore-not-found --wait=false || true
  kubectl -n "$ns" delete kafkausers.kafka.strimzi.io --all --ignore-not-found --wait=false || true
  kubectl -n "$ns" delete kafkas.kafka.strimzi.io --all --ignore-not-found --wait=false || true
}

# ------------------------ VerneMQ --------------------------------------------
echo "🔧 Uninstalling VerneMQ..."
helm uninstall vernemq -n "${VERNEMQ_NS}" || true

if [[ "$PURGE_NS" == "true" ]]; then
  echo "Deleting namespace: $VERNEMQ_NS"
  kubectl delete ns "${VERNEMQ_NS}" --ignore-not-found=true || true
fi

# ------------- UIs & Ingresses -----------------------------------------------
hr
echo "Uninstalling Traefik dashboard ingress, Headlamp and Longhorn UI..."

helm_uninstall "$TRAEFIK_NS" "traefik-dashboard"

helm_uninstall "$HEADLAMP_NS" "headlamp"
if [[ "$PURGE_NS" == "true" ]]; then
  echo "Deleting namespace: $HEADLAMP_NS"
  kubectl delete ns "$HEADLAMP_NS" --ignore-not-found || true
fi

helm_uninstall "$GRAFANA_NS" "grafana"
if [[ "$PURGE_NS" == "true" ]]; then
  echo "Deleting namespace: $GRAFANA_NS"
  kubectl delete ns "$GRAFANA_NS" --ignore-not-found || true
fi

helm_uninstall "$LONGHORN_NS" "longhorn-ui"
# (We do NOT delete the longhorn-system namespace or Longhorn itself.)

# ------------------------ ClickHouse backup -------------------------------------
echo "Uninstalling ClickHouse backup CronJobs (daily + hourly + cleanup)..."
helm_uninstall "$CLICKHOUSE_NS" "clickhouse-backup"

# ------------- ClickHouse -----------------------------------------------
hr
echo "Uninstalling ClickHouse and Altinity Kubernetes Operator for ClickHouse..."

# Delete ClickHouse custom resources first (so the operator can clean up)
kubectl -n "$CLICKHOUSE_NS" delete clickhouseinstallations.clickhouse.altinity.com --all --ignore-not-found || true
kubectl -n "$CLICKHOUSE_NS" delete clickhousekeeperinstallations.clickhouse-keeper.altinity.com --all --ignore-not-found || true

# Then uninstall charts
helm_uninstall "$CLICKHOUSE_NS" "clickhouse"
helm_uninstall "$CLICKHOUSE_NS" "clickhouse-operator"

# Optional: delete PVCs if you’re purging the namespace and want storage gone
if [[ "$PURGE_NS" == "true" ]]; then
  echo "Deleting ClickHouse namespace: $CLICKHOUSE_NS"
  kubectl delete all --all -n "$CLICKHOUSE_NS" --ignore-not-found --grace-period=0 --force --wait=false || true
  kubectl delete secret --all -n "$CLICKHOUSE_NS" --ignore-not-found --grace-period=0 --force --wait=false || true
  kubectl -n "$CLICKHOUSE_NS" delete pvc --all --ignore-not-found || true
  kubectl delete ns "$CLICKHOUSE_NS" --ignore-not-found --wait=false || true
  if kubectl get ns "$CLICKHOUSE_NS" >/dev/null 2>&1; then
    echo "Best-effort finalizer removal step 1. for $CLICKHOUSE_NS namespaces"
	kubectl get ns "$CLICKHOUSE_NS" -o json \
      | jq 'del(.spec.finalizers)' \
      | kubectl replace --raw "/api/v1/namespaces/$CLICKHOUSE_NS/finalize" -f - || true
  fi
  if kubectl get ns "$CLICKHOUSE_NS" >/dev/null 2>&1; then
    echo "Best-effort finalizer removal step 2. for $CLICKHOUSE_NS namespaces"
    kubectl get ns "$CLICKHOUSE_NS" -o json \
      | jq '.spec.finalizers=[]' \
      | kubectl replace --raw "/api/v1/namespaces/$CLICKHOUSE_NS/finalize" -f - || true
  fi
fi

# Optional: delete ONLY ClickHouse CRDs (not all CRDs!)
if [[ "$DELETE_CLICKHOUSE_CRDS" == "true" ]]; then
  kubectl delete crd \
    clickhouseinstallations.clickhouse.altinity.com \
    clickhouseinstallationtemplates.clickhouse.altinity.com \
    clickhousekeeperinstallations.clickhouse-keeper.altinity.com \
    clickhouseoperatorconfigurations.clickhouse.altinity.com \
    --ignore-not-found || true
fi

# ------------- Kafka & Kafka Connect & Strimzi -----------------------------------------------
hr
echo "Uninstalling Kafka UI, Kafka cluster and Strimzi operator..."

helm_uninstall "$KAFKA_NS" "kafka-ui"
helm_uninstall "$KAFKA_NS" "kafka-connect"
helm_uninstall "$KAFKA_NS" "kafka-cluster"

# In case Helm uninstall didn’t remove CRs (or install was interrupted)
delete_strimzi_crs "$KAFKA_NS"

helm_uninstall "$KAFKA_NS" "strimzi-operator"

# ------------- Kafka Local Storage (PVs chart) -------------------------------
hr
echo "Uninstalling Kafka local storage Helm release..."
helm_uninstall "$KAFKA_NS" "kafka-local-storage"

# Optionally delete PVCs and the Kafka namespace
if [[ "$PURGE_NS" == "true" ]]; then
  echo "Deleting all PVCs in namespace: $KAFKA_NS"
  kubectl -n "$KAFKA_NS" delete pvc --all --ignore-not-found || true

  echo "Deleting namespace: $KAFKA_NS"
  kubectl delete ns "$KAFKA_NS" --ignore-not-found --wait=false || true
  # Best-effort finalizer removal if stuck
  if kubectl get ns "$KAFKA_NS" >/dev/null 2>&1; then
    kubectl get ns "$KAFKA_NS" -o json \
      | jq '.spec.finalizers=[]' \
      | kubectl replace --raw "/api/v1/namespaces/$KAFKA_NS/finalize" -f - || true
  fi
fi

# Optionally delete PV objects created by the local-storage chart
if [[ "$DELETE_PVS" == "true" ]]; then
  hr
  echo "Deleting PV objects (reclaimPolicy=Retain may have left them)..."
  for pv in "${CTRL_PVS[@]}" "${BROKER_PVS[@]}"; do
    echo "Deleting PV: $pv"
    kubectl delete pv "$pv" --ignore-not-found || true
  done
  echo "NOTE: The PVs pointed to hostPath directories (e.g., /var/lib/kafka)."
  echo "      You may manually wipe data on each node if you want a clean slate."
fi

# Optionally delete /var/lib/kafka/* on nodes
if [[ "$DEL_VAR_LIB_KAFKA" == "true" ]]; then
  hr
  echo "Deleting /var/lib/kafka/* on nodes (reclaimPolicy=Retain may have left them)..."
  ansible controlplane -i ~/alpine-k3s/hosts -m raw -b -a 'rm -rf /var/lib/kafka/*' || true
  ansible worker       -i ~/alpine-k3s/hosts -m raw -b -a 'rm -rf /var/lib/kafka/*' || true
  echo "Deleted /var/lib/kafka/* on nodes."
fi

# ------------- Summary -------------------------------------------------------
hr
echo "Uninstall complete."

if [[ "$PURGE_NS" != "true" ]]; then
  echo "Namespaces kept. To also delete them: PURGE_NS=true ./uninstall.sh"
fi
if [[ "$DELETE_PVS" != "true" ]]; then
  echo "PV objects kept. To also delete them: DELETE_PVS=true ./uninstall.sh"
fi

echo "You can verify remaining objects with:"
echo "  kubectl get ns"
echo "  kubectl get pv"
echo "  kubectl get all -A | grep -E '(kafka|headlamp)' || true"
