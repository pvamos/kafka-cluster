#!/usr/bin/env bash
# install.sh
#
# End-to-end installer for:
# - Local Kafka storage (PVs + StorageClass)
# - Strimzi operator
# - Kafka 4.0.0 cluster (Strimzi)
# - Kafka UI
# - Longhorn UI Ingress
# - Headlamp
# - Traefik dashboard Ingress
# - VerneMQ (HostPort :1883, PROXY v2)
# - ClickHouse (Altinity operator + CHI + Keeper + Kafka Engine ingest)
# - Grafana (ClickHouse datasource provisioned)
#
# IMPORTANT (secrets policy for VerneMQ):
# - All VerneMQ-related secrets are created here, not by Helm templates.
# - We create a single API key in Secret "emqx-api-key" and use it:
#     * VerneMQ bootstrap via EMQX_API_KEY__BOOTSTRAP_FILE (apikeys.conf)
# - We also create "emqx-secret" for the dashboard admin UI: keys {user, pass}
#

set -euo pipefail

# ------------- Config parameters ---------------------------------------------
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"

# Paths to local charts
CHART_KAFKA_LOCAL_STORAGE="kafka-local-storage"
CHART_STRIMZI_REPO="strimzi/strimzi-kafka-operator"
CHART_STRIMZI="kafka"
CHART_KAFKA_CLUSTER="kafka"
CHART_KAFKA_CONNECT="kafka-connect"
CHART_KAFKA_UI="kafka-ui"
CHART_LONGHORN_UI="longhorn-ui"
CHART_HEADLAMP="headlamp"
CHART_TRAEFIK_DASHBOARD="traefik-dashboard"
CHART_VERNEMQ="vernemq"
CHART_CLICKHOUSE="clickhouse"
CHART_CLICKHOUSE_BACKUP="clickhouse-backup"
CHART_GRAFANA="grafana"

# Read namespaces from local charts
KAFKA_NS="$(yq e '.namespace' "${SCRIPTDIR}/${CHART_KAFKA_CLUSTER}/values.yaml")"
KAFKA_CONNECT_NS="$(yq e '.namespace' "${SCRIPTDIR}/${CHART_KAFKA_CONNECT}/values.yaml")"
KAFKA_UI_NS="$(yq e '.namespace' "${SCRIPTDIR}/${CHART_KAFKA_UI}/values.yaml")"
LONGHORN_UI_NS="$(yq e '.namespace' "${SCRIPTDIR}/${CHART_LONGHORN_UI}/values.yaml")"
HEADLAMP_NS="$(yq e '.namespace' "${SCRIPTDIR}/${CHART_HEADLAMP}/values.yaml")"
TRAEFIK_DASHBOARD_NS="$(yq e '.namespace' "${SCRIPTDIR}/${CHART_TRAEFIK_DASHBOARD}/values.yaml")"
VERNEMQ_NS="$(yq e '.namespace' "${SCRIPTDIR}/${CHART_VERNEMQ}/values.yaml")"
CLICKHOUSE_NS="$(yq e '.namespace' "${SCRIPTDIR}/${CHART_CLICKHOUSE}/values.yaml")"
GRAFANA_NS="$(yq e '.namespace' "${SCRIPTDIR}/${CHART_GRAFANA}/values.yaml")"

# Release names
KAFKA_LOCAL_STORAGE_RELEASE="kafka-local-storage"
STRIMZI_RELEASE="strimzi-operator"
KAFKA_CLUSTER_RELEASE="kafka-cluster"
KAFKA_CONNECT_RELEASE="kafka-connect"
KAFKA_UI_RELEASE="kafka-ui"
HEADLAMP_RELEASE="headlamp"
LONGHORN_RELEASE="longhorn-ui"
TRAEFIK_DASHBOARD_RELEASE="traefik-dashboard"
VERNEMQ_RELEASE="vernemq"
CLICKHOUSE_OPERATOR_RELEASE="clickhouse-operator"
CLICKHOUSE_RELEASE="clickhouse"
CLICKHOUSE_BACKUP_RELEASE="clickhouse-backup"
GRAFANA_RELEASE="grafana"

# Strimzi Operator helm chart version
STRIMZI_OPERATOR_VERSION="$(yq e '.strimziOperatorVersion' "${SCRIPTDIR}/${CHART_STRIMZI}/values.yaml")"

KAFKA_CLUSTER_NAME="$(yq e '.kafka.clusterName' "${SCRIPTDIR}/${CHART_KAFKA_CLUSTER}/values.yaml")"
KAFKA_BOOTSTRAP="${KAFKA_CLUSTER_NAME}-kafka-bootstrap.${KAFKA_NS}.svc.cluster.local:9092"
KAFKA_BOOTSTRAP_SVC="${KAFKA_CLUSTER_NAME}-kafka-bootstrap"
# Load Kafka UI username
KAFKA_UI_USERNAME="$(yq e '.kafkaUIauth.username' "$SCRIPTDIR/${CHART_KAFKA_UI}/values.yaml")"

# Kafka topic used for sensor readings
KAFKA_TOPIC="sensors"

# PV names used with kafka-local-storage chart
CTRL_PVS=($(yq '.controllerPersistentVolumes[].name' "${SCRIPTDIR}/${CHART_KAFKA_LOCAL_STORAGE}/values.yaml" | xargs))
BROKER_PVS=($(yq '.brokerPersistentVolumes[].name' "${SCRIPTDIR}/${CHART_KAFKA_LOCAL_STORAGE}/values.yaml" | xargs))

# Load Headlamp serviceAccount name from Headlamp values
HEADLAMP_SERVICEACCOUNT="$(yq e '.headlamp.serviceAccount.name' "$SCRIPTDIR/${CHART_HEADLAMP}/values.yaml")"

HARBOR_ROBOT_TOKEN="CHANGE_ME_REGISTRY_ROBOT_TOKEN"

CLICKHOUSE_OPERATOR_VERSION="0.25.5"

CLICKHOUSE_PASSWORD="CHANGE_ME_CLICKHOUSE_PASSWORD"
CLICKHOUSE_PASSWORD_SHA="$(printf '%s' "$CLICKHOUSE_PASSWORD" | sha256sum | awk '{print $1}')"

# ClickHouse chart values we need for waits/verification
CLICKHOUSE_CHI_NAME="$(yq e '.chi.name' "${SCRIPTDIR}/${CHART_CLICKHOUSE}/values.yaml")"
CLICKHOUSE_DB_NAME="$(yq e '.db.name' "${SCRIPTDIR}/${CHART_CLICKHOUSE}/values.yaml")"
CLICKHOUSE_DB_TABLE="$(yq e '.db.table' "${SCRIPTDIR}/${CHART_CLICKHOUSE}/values.yaml")"
CLICKHOUSE_SHARDS="$(yq e '.chi.shards' "${SCRIPTDIR}/${CHART_CLICKHOUSE}/values.yaml")"
CLICKHOUSE_REPLICAS="$(yq e '.chi.replicas' "${SCRIPTDIR}/${CHART_CLICKHOUSE}/values.yaml")"

# S3 backup secret
S3_BACKUP_SECRET="clickhouse-backup-s3"
S3_BACKUP_ENDPOINT="https://s3.example.com"
S3_BACKUP_REGION="example-region"
S3_BACKUP_BUCKET="example-clickhouse-backup"
S3_BACKUP_ACCESS_KEY_ID="CHANGE_ME_S3_BACKUP_ACCESS_KEY_ID"
S3_BACKUP_SECRET_ACCESS_KEY="CHANGE_ME_S3_BACKUP_SECRET_ACCESS_KEY"

# S3 backup marker secret
S3_BACKUP_MARKER_SECRET="clickhouse-backup-marker-s3"
S3_BACKUP_MARKER_ENDPOINT="https://s3.example.com"
S3_BACKUP_MARKER_REGION="example-region"
S3_BACKUP_MARKER_BUCKET="example-clickhouse-backup-marker"
S3_BACKUP_MARKER_ACCESS_KEY_ID="CHANGE_ME_S3_BACKUP_MARKER_ACCESS_KEY_ID"
S3_BACKUP_MARKER_SECRET_ACCESS_KEY="CHANGE_ME_S3_BACKUP_MARKER_SECRET_ACCESS_KEY"

# S3 data lake secret
S3_LAKE_SECRET="clickhouse-lake-s3"
S3_LAKE_ENDPOINT="https://s3.example.com"
S3_LAKE_REGION="example-region"
S3_LAKE_BUCKET="example-lake"
S3_LAKE_ACCESS_KEY_ID="CHANGE_ME_S3_LAKE_ACCESS_KEY_ID"
S3_LAKE_SECRET_ACCESS_KEY="CHANGE_ME_S3_LAKE_SECRET_ACCESS_KEY"

# S3 data lake read only secret
S3_LAKE_READ_SECRET="clickhouse-lake-s3-read"
S3_LAKE_READ_ENDPOINT="https://s3.example.com"
S3_LAKE_READ_REGION="example-region"
S3_LAKE_READ_BUCKET="example-lake"
S3_LAKE_READ_ACCESS_KEY_ID="CHANGE_ME_S3_LAKE_READ_ACCESS_KEY_ID"
S3_LAKE_READ_SECRET_ACCESS_KEY="CHANGE_ME_S3_LAKE_READ_SECRET_ACCESS_KEY"

GRAFANA_ADMIN_USER="$(yq e '.grafanaAdmin.user' "$SCRIPTDIR/${CHART_GRAFANA}/values.yaml")"
GRAFANA_ADMIN_PASSWORD="$(yq e '.grafanaAdmin.password' "$SCRIPTDIR/${CHART_GRAFANA}/values.yaml")"

# -------------------------------- helpers -------------------------------------
bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
note()  { echo "$*"; }
die()   { echo "ERROR: $*" >&2; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

needed_bins() {
  for b in kubectl helm openssl yq; do
    have "$b" || die "Missing required binary: $b"
  done
}

wait_pv_available() {
  local pv="$1"
  printf "persistentvolume/%s " "$pv"
  for i in {1..120}; do
    phase=$(kubectl get pv "$pv" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$phase" == "Available" || "$phase" == "Bound" ]]; then
      echo "condition met"
      return 0
    fi
    sleep 2
  done
  echo "timed out waiting for PV=$pv to be Available/Bound"
  return 1
}

wait_ns() {
  local ns="$1"
  kubectl wait --for=jsonpath='{.status.phase}'=Active "ns/${ns}" --timeout=300s
}

wait_opaque_secret() {
  local ns="$1"
  local secret="$2"
  kubectl -n "${ns}" wait --for=jsonpath='{.type}'=Opaque "secret/${secret}" --timeout=300s
}

wait_deploy_ready() {
  local ns="$1" name="$2"
  kubectl -n "$ns" rollout status deploy/"$name" --timeout=120s
}

wait_service() {
  local ns="$1" svc="$2"
  local tries=50
  local sleep_s=5
  local i=0
  while (( i < tries )); do
    if kubectl -n "$ns" get svc "$svc" >/dev/null 2>&1; then
      return 0
    fi
    echo "⏳ Service not ready yet. Waiting ${sleep_s} seconds..."
    sleep "$sleep_s"
    i=$((i+1))
  done
  return 1
}

wait_pod_selector_ready() {
  local ns="$1" sel="$2"
  kubectl -n "$ns" wait --for=condition=Ready pods -l "$sel" --timeout=600s
}

wait_job_complete() {
  local ns="$1" job="$2" timeout="${3:-1200s}"
  if kubectl -n "$ns" wait --for=condition=complete "job/${job}" --timeout="${timeout}"; then
    return 0
  fi
  echo "❌ Job ${job} did not complete in ${timeout}."
  kubectl -n "$ns" get job "$job" -o wide || true
  kubectl -n "$ns" describe job "$job" || true
  kubectl -n "$ns" logs -l job-name="$job" --all-containers --tail=200 || true
  return 1
}

ensure_envsensor_secret() {
  local ns="$1"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  if ! kubectl -n "$ns" get secret envsensor-reg >/dev/null 2>&1; then
    if [ -z "${HARBOR_ROBOT_TOKEN}" ]; then
      echo "❌ HARBOR_ROBOT_TOKEN not set."
      exit 1
    fi
    kubectl -n "$ns" create secret docker-registry envsensor-reg \
      --docker-server=reg.envsensor.net \
      --docker-username='robot$envsensor+pull' \
      --docker-password="${HARBOR_ROBOT_TOKEN}" \
      --docker-email='ci@envsensor.net'
    echo "✅ Created image pull secret 'envsensor-reg' in namespace ${ns}."
  else
    echo "ℹ️ Image pull secret 'envsensor-reg' already exists in namespace ${ns}, reusing."
  fi
}

ensure_clickhouse_kafka_auth() {
  local kafka_user="consumer"
  local auth_secret="clickhouse-kafka-auth"

  kubectl create namespace "${CLICKHOUSE_NS}" --dry-run=client -o yaml | kubectl apply -f -

  local pw_b64
  pw_b64="$(kubectl -n "${KAFKA_NS}" get secret "${kafka_user}" -o jsonpath='{.data.password}')"
  if [[ -z "${pw_b64}" ]]; then
    die "Could not read .data.password from secret/${kafka_user} in ns=${KAFKA_NS}"
  fi

  local pw
  pw="$(echo "${pw_b64}" | base64 -d)"

  kubectl -n "${CLICKHOUSE_NS}" delete secret "${auth_secret}" >/dev/null 2>&1 || true
  kubectl -n "${CLICKHOUSE_NS}" create secret generic "${auth_secret}" \
    --from-literal=username="${kafka_user}" \
    --from-literal=password="${pw}"
}

verify_clickhouse_schema_all_pods() {
  local ns="$1" chi="$2" db="$3" table="$4"

  local ch_user ch_pass
  ch_user="$(kubectl -n "${ns}" get secret clickhouse-auth -o jsonpath='{.data.username}' | base64 -d)"
  ch_pass="$(kubectl -n "${ns}" get secret clickhouse-auth -o jsonpath='{.data.password}' | base64 -d)"

  local pods
  pods="$(kubectl -n "${ns}" get pod -l "clickhouse.altinity.com/chi=${chi}" -o jsonpath='{.items[*].metadata.name}')"
  [[ -n "$pods" ]] || die "No ClickHouse pods found with label clickhouse.altinity.com/chi=${chi}"

  local bad=0
  for p in $pods; do
    echo "🔎 Verifying schema on $p ..."
    local has_db has_tbl
    has_db="$(kubectl -n "${ns}" exec -i "$p" -- clickhouse-client \
      -u "$ch_user" --password "$ch_pass" \
      --query "SELECT count() FROM system.databases WHERE name='${db}';" | tr -d '[:space:]')"

    has_tbl="$(kubectl -n "${ns}" exec -i "$p" -- clickhouse-client \
      -u "$ch_user" --password "$ch_pass" \
      --query "SELECT count() FROM system.tables WHERE database='${db}' AND name='${table}';" | tr -d '[:space:]')"

    if [[ "$has_db" != "1" || "$has_tbl" != "1" ]]; then
      echo "❌ $p missing schema: db=${has_db} table=${has_tbl}"
      bad=1
    else
      echo "✅ $p ok"
    fi
  done

  [[ "$bad" -eq 0 ]] || die "ClickHouse schema is not present on all replicas (this would cause Grafana UNKNOWN_DATABASE intermittently)."
}

# wait_clickhouse_ddl_queue_ready() {
  # local ns="$CLICKHOUSE_NS" chi="$CLICKHOUSE_CHI_NAME"
  # local expected=$((CLICKHOUSE_SHARDS * CLICKHOUSE_REPLICAS))

  # bold "⏳ Waiting for ClickHouse DDL queue to register ${expected} replicas at /clickhouse/task_queue/replicas ..."

  # local pod
  # pod="$(kubectl -n "$ns" get pod -l "clickhouse.altinity.com/chi=${chi}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  # if [[ -z "$pod" ]]; then
    # note "⚠️ No ClickHouse pods found yet when checking DDL queue; skipping check."
    # return 1
  # fi

  # for i in $(seq 1 120); do
    # local children
    # children="$(kubectl -n "$ns" exec -i "$pod" -- clickhouse-client \
      # -u default --password "$CLICKHOUSE_PASSWORD" \
      # --query "SELECT ifNull(max(numChildren),0) FROM system.zookeeper WHERE path='/clickhouse/task_queue/replicas' SETTINGS allow_unrestricted_reads_from_keeper = 1" 2>/dev/null || echo 0)"
    # children="$(echo "$children" | tr -d '[:space:]')"

    # if [[ "$children" =~ ^[0-9]+$ ]] && (( children >= expected )); then
      # note "✅ DDL queue has ${children} replicas (expected >= ${expected})."
      # return 0
    # fi

    # sleep 2
  # done

  # echo "❌ DDL queue did not reach expected replicas (expected=${expected}). Current state:"
  # kubectl -n "$ns" exec -i "$pod" -- clickhouse-client \
    # -u default --password "$CLICKHOUSE_PASSWORD" \
    # --query "SELECT path, name, numChildren FROM system.zookeeper WHERE path IN ('/clickhouse/task_queue/replicas','/clickhouse/clickhouse/task_queue/replicas') ORDER BY path, name SETTINGS allow_unrestricted_reads_from_keeper = 1" || true

  # die "ClickHouse DDL queue is not healthy; refusing to proceed with init job."
# }

ensure_clickhouse_backup_s3_secret() {
  # ClickHouse named collection expects a base URL; we use path-style:
  local url="${S3_BACKUP_ENDPOINT%/}/${S3_BACKUP_BUCKET}/"

  kubectl -n "${CLICKHOUSE_NS}" create secret generic "${S3_BACKUP_SECRET}" \
    --from-literal=url="${url}" \
    --from-literal=region="${S3_BACKUP_REGION}" \
    --from-literal=endpoint="${S3_BACKUP_ENDPOINT}" \
    --from-literal=bucket="${S3_BACKUP_BUCKET}" \
    --from-literal=access_key_id="${S3_BACKUP_ACCESS_KEY_ID}" \
    --from-literal=secret_access_key="${S3_BACKUP_SECRET_ACCESS_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

ensure_clickhouse_backup_marker_s3_secret() {
  # ClickHouse named collection expects a base URL; we use path-style:
  local url="${S3_BACKUP_MARKER_ENDPOINT%/}/${S3_BACKUP_MARKER_BUCKET}/"

  kubectl -n "${CLICKHOUSE_NS}" create secret generic "${S3_BACKUP_MARKER_SECRET}" \
    --from-literal=url="${url}" \
    --from-literal=region="${S3_BACKUP_MARKER_REGION}" \
    --from-literal=endpoint="${S3_BACKUP_MARKER_ENDPOINT}" \
    --from-literal=bucket="${S3_BACKUP_MARKER_BUCKET}" \
    --from-literal=access_key_id="${S3_BACKUP_MARKER_ACCESS_KEY_ID}" \
    --from-literal=secret_access_key="${S3_BACKUP_MARKER_SECRET_ACCESS_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

ensure_clickhouse_lake_s3_secret() {
  # ClickHouse named collection expects a base URL; we use path-style:
  local url="${S3_LAKE_ENDPOINT%/}/${S3_LAKE_BUCKET}/"

  kubectl -n "${CLICKHOUSE_NS}" create secret generic "${S3_LAKE_SECRET}" \
    --from-literal=url="${url}" \
    --from-literal=region="${S3_LAKE_REGION}" \
    --from-literal=endpoint="${S3_LAKE_ENDPOINT}" \
    --from-literal=bucket="${S3_LAKE_BUCKET}" \
    --from-literal=access_key_id="${S3_LAKE_ACCESS_KEY_ID}" \
    --from-literal=secret_access_key="${S3_LAKE_SECRET_ACCESS_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

ensure_clickhouse_lake_s3_read_secret() {
  # ClickHouse named collection expects a base URL; we use path-style:
  local url="${S3_LAKE_ENDPOINT%/}/${S3_LAKE_BUCKET}/"

  kubectl -n "${CLICKHOUSE_NS}" create secret generic "${S3_LAKE_READ_SECRET}" \
    --from-literal=url="${url}" \
    --from-literal=region="${S3_LAKE_READ_REGION}" \
    --from-literal=endpoint="${S3_LAKE_READ_ENDPOINT}" \
    --from-literal=bucket="${S3_LAKE_READ_BUCKET}" \
    --from-literal=access_key_id="${S3_LAKE_READ_ACCESS_KEY_ID}" \
    --from-literal=secret_access_key="${S3_LAKE_READ_SECRET_ACCESS_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# -------------------------------- preflight -----------------------------------
needed_bins

# ------------------------ VerneMQ ---------------------------------------------
bold "🚜 Preparing VerneMQ namespace & image pull secret..."
kubectl get ns "${VERNEMQ_NS}" >/dev/null 2>&1 || kubectl create ns "${VERNEMQ_NS}" --dry-run=client -o yaml | kubectl apply -f -
wait_ns "${VERNEMQ_NS}"

ensure_envsensor_secret "${VERNEMQ_NS}"

bold "🚀 Deploying VerneMQ 3-node cluster..."
kubectl create namespace "${VERNEMQ_NS}" --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install "${VERNEMQ_RELEASE}" "${SCRIPTDIR}/${CHART_VERNEMQ}" -n "${VERNEMQ_NS}" -f "${SCRIPTDIR}/${CHART_VERNEMQ}/values.yaml"

bold "⏳ Waiting for VerneMQ pods to be ready..."
note "✅ VerneMQ deployed."

# ------------- Kafka: namespace + local storage PVs --------------------------
bold "📦 Creating Kubernetes namespace: ${KAFKA_NS}"
kubectl get ns "${KAFKA_NS}" >/dev/null 2>&1 || kubectl create ns "${KAFKA_NS}" --dry-run=client -o yaml | kubectl apply -f -
wait_ns "${KAFKA_NS}"

ensure_envsensor_secret "${KAFKA_NS}"

bold "💾 Deploying Kafka Local Storage (PVs & StorageClass)..."
helm upgrade --install "${KAFKA_LOCAL_STORAGE_RELEASE}" "${SCRIPTDIR}/${CHART_KAFKA_LOCAL_STORAGE}" -n "${KAFKA_NS}"

bold "⏳ Waiting for Kafka Controller PVs to become Available..."
for pv in "${CTRL_PVS[@]}"; do wait_pv_available "$pv"; done

bold "⏳ Waiting for Kafka Broker PVs to become Available..."
for pv in "${BROKER_PVS[@]}"; do wait_pv_available "$pv"; done

note "✅ Kafka Local Storage (PVs & StorageClass) has been deployed."

# ------------------------- Strimzi Kafka Operator -----------------------------
bold "👷 Installing Strimzi Kafka Operator..."
helm repo add strimzi https://strimzi.io/charts/ >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
helm upgrade --install "${STRIMZI_RELEASE}" "${CHART_STRIMZI_REPO}" \
  --version "${STRIMZI_OPERATOR_VERSION}" -n "${KAFKA_NS}" -f "${SCRIPTDIR}/${CHART_STRIMZI}/operator-values.yaml"

bold "⏳ Waiting for Strimzi Operator deployment to be ready..."
wait_deploy_ready "${KAFKA_NS}" "strimzi-cluster-operator"

note "✅ Strimzi Kafka Operator has been installed."

# ----------------------------- Kafka Cluster ----------------------------------
bold "🚀 Deploying Kafka Cluster with Strimzi..."
helm repo update >/dev/null 2>&1 || true
helm upgrade --install "${KAFKA_CLUSTER_RELEASE}" "${SCRIPTDIR}/${CHART_KAFKA_CLUSTER}" -n "${KAFKA_NS}" -f "${SCRIPTDIR}/${CHART_KAFKA_CLUSTER}/values.yaml"

bold "⏳ Waiting for Kafka bootstrap service to be ready..."
if wait_service "${KAFKA_NS}" "${KAFKA_BOOTSTRAP_SVC}"; then
  note "service/${KAFKA_BOOTSTRAP_SVC} condition met"
  note "✅ ${KAFKA_BOOTSTRAP_SVC} service is available. Waiting 30 seconds..."
  sleep 30
else
  die "${KAFKA_BOOTSTRAP_SVC} service not found"
fi

bold "⏳ Wait for Kafka Controllers and Brokers to be ready..."
kubectl -n "${KAFKA_NS}" wait --for=condition=Ready pod \
  -l "strimzi.io/cluster=${KAFKA_CLUSTER_NAME},strimzi.io/kind=Kafka,app.kubernetes.io/name=kafka" --timeout=300s || true

bold "⏳ Wait for Kafka topic ${KAFKA_TOPIC} to be ready..."
kubectl -n "${KAFKA_NS}" wait --for=condition=Ready kafkatopic "${KAFKA_TOPIC}" --timeout=300s || true


note "✅ Kafka Cluster has been deployed."

# -------------------------------- Kafka UI ------------------------------------
bold "⏳ Waiting for kafkauser ${KAFKA_UI_USERNAME}..."
kubectl wait --for=condition=Ready kafkauser "${KAFKA_UI_USERNAME}" -n "${KAFKA_NS}" --timeout=300s || true

bold "🎛 Deploying Kafka UI..."
helm upgrade --install "${KAFKA_UI_RELEASE}" "${SCRIPTDIR}/${CHART_KAFKA_UI}" -n "${KAFKA_NS}" -f "${SCRIPTDIR}/${CHART_KAFKA_UI}/values.yaml"

bold "⏳ Waiting for Kafka UI to be ready..."
wait_pod_selector_ready "${KAFKA_NS}" "app=kafka-ui" || true
wait_service "${KAFKA_NS}" "${KAFKA_UI_RELEASE}" || true

note "✅ Kafka UI has been deployed."

# --------------------------- Longhorn UI Ingress ------------------------------
bold "⏳ Waiting for Longhorn UI service to be ready..."
wait_service "${LONGHORN_UI_NS}" "longhorn-frontend" || true

bold "🔐 Deploying Longhorn UI Ingress..."
helm upgrade --install "${LONGHORN_RELEASE}" "${SCRIPTDIR}/${CHART_LONGHORN_UI}" -n "${LONGHORN_UI_NS}" -f "${SCRIPTDIR}/${CHART_LONGHORN_UI}/values.yaml"

bold "⏳ Waiting for Longhorn UI Ingress to be ready..."
kubectl -n "${LONGHORN_UI_NS}" wait --for=jsonpath='{.status.loadBalancer.ingress}' ingress/longhorn-ui --timeout=300s || true

note "✅ Longhorn UI Ingress has been deployed."

# -------------------------------- Headlamp ------------------------------------
bold "📦 Creating Kubernetes namespace: ${HEADLAMP_NS}"
kubectl get ns "${HEADLAMP_NS}" >/dev/null 2>&1 || kubectl create ns "${HEADLAMP_NS}" --dry-run=client -o yaml | kubectl apply -f -
wait_ns "${HEADLAMP_NS}"

bold "🔄 Updating Headlamp helm chart dependency..."
helm dependency update "./${CHART_HEADLAMP}" || true
helm dependency list "./${CHART_HEADLAMP}" || true

bold "🔦 Deploying Headlamp dashboard..."
helm upgrade --install "${HEADLAMP_RELEASE}" "./${CHART_HEADLAMP}" -n "${HEADLAMP_NS}" -f "${SCRIPTDIR}/${CHART_HEADLAMP}/values.yaml"

bold "⏳ Waiting for Headlamp dashboard to be ready..."
wait_pod_selector_ready "${HEADLAMP_NS}" "app.kubernetes.io/name=headlamp" || true
wait_service "${HEADLAMP_NS}" "headlamp" || true

note "✅ Headlamp has been deployed."

# ------------------------ Traefik Dashboard Ingress ---------------------------
bold "🔐 Deploying Traefik Dasboard Ingress..."
helm upgrade --install "${TRAEFIK_DASHBOARD_RELEASE}" "${CHART_TRAEFIK_DASHBOARD}" -n "${TRAEFIK_DASHBOARD_NS}"

note "✅ Traefik Dasboard Ingress has been deployed."

# ------------------------ Kafka Connect ---------------------------------------
bold "⏳ Wait for Kafka topics created by operator to be ready before deploying Kafka Connect cluster..."
kubectl -n "${KAFKA_NS}" wait --for=condition=Ready kafkatopic -l "strimzi.io/cluster=${KAFKA_CLUSTER_NAME}" --timeout=300s || true

bold "🚀 Deploying Kafka Connect cluster..."
helm upgrade --install "${KAFKA_CONNECT_RELEASE}" "${SCRIPTDIR}/${CHART_KAFKA_CONNECT}" \
  -n "${KAFKA_CONNECT_NS}" -f "${SCRIPTDIR}/${CHART_KAFKA_CONNECT}/values.yaml"

bold "⏳ Waiting for Kafka Connect pods to be ready..."
sleep 5
wait_pod_selector_ready "${KAFKA_CONNECT_NS}" "strimzi.io/kind=KafkaConnect,strimzi.io/name=$(yq e '.connect.name' ${SCRIPTDIR}/${CHART_KAFKA_CONNECT}/values.yaml)-connect"

note "✅ Kafka Connect deployed."

# ------------------------ ClickHouse -----------------------------------------
bold "📦 Creating Kubernetes namespace: ${CLICKHOUSE_NS}"
kubectl get ns "${CLICKHOUSE_NS}" >/dev/null 2>&1 || kubectl create ns "${CLICKHOUSE_NS}" --dry-run=client -o yaml | kubectl apply -f -
wait_ns "${CLICKHOUSE_NS}"
note "✅ ClickHouse Kubernetes namespace: ${CLICKHOUSE_NS} created."

bold "🔐 Ensuring ClickHouse backup S3 secret..."
ensure_clickhouse_backup_s3_secret
wait_opaque_secret "${CLICKHOUSE_NS}" "${S3_BACKUP_SECRET}"
note "✅ ClickHouse backup S3 secret created."

bold "🔐 Ensuring ClickHouse backup marker S3 secret..."
ensure_clickhouse_backup_marker_s3_secret
wait_opaque_secret "${CLICKHOUSE_NS}" "${S3_BACKUP_MARKER_SECRET}"
note "✅ ClickHouse backup marker S3 secret created."

bold "🔐 Ensuring ClickHouse data lake S3 secret..."
ensure_clickhouse_lake_s3_secret
wait_opaque_secret "${CLICKHOUSE_NS}" "${S3_LAKE_SECRET}"
note "✅ ClickHouse data lake S3 secret created."

bold "🔐 Ensuring ClickHouse data lake S3 read only secret..."
ensure_clickhouse_lake_s3_read_secret
wait_opaque_secret "${CLICKHOUSE_NS}" "${S3_LAKE_READ_SECRET}"
note "✅ ClickHouse data lake S3 read only secret created."

bold "👷 Installing Altinity ClickHouse Operator..."
helm repo add altinity https://helm.altinity.com >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
helm upgrade --install "${CLICKHOUSE_OPERATOR_RELEASE}" altinity/altinity-clickhouse-operator \
  --version="${CLICKHOUSE_OPERATOR_VERSION}" -n "${CLICKHOUSE_NS}"

bold "⏳ Waiting for Altinity ClickHouse Operator deployments to be ready..."
kubectl -n "${CLICKHOUSE_NS}" rollout status deploy --timeout=300s
note "✅ ClickHouse Altinity ClickHouse Operator deployed."

bold "🔐 Creating/Updating ClickHouse 'clickhouse-auth' secret..."
kubectl -n "${CLICKHOUSE_NS}" create secret generic clickhouse-auth \
  --from-literal=username=default \
  --from-literal=password="$CLICKHOUSE_PASSWORD" \
  --from-literal=password_sha256_hex="$CLICKHOUSE_PASSWORD_SHA" \
  --dry-run=client -o yaml | kubectl apply -f -

bold "🔐 Creating ClickHouse Kafka auth secret..."
ensure_clickhouse_kafka_auth

bold "🔐 Creating ClickHouse inter-cluster secret (do NOT rotate on reruns)..."
if ! kubectl -n "${CLICKHOUSE_NS}" get secret clickhouse-intercluster-communications >/dev/null 2>&1; then
  kubectl -n "${CLICKHOUSE_NS}" create secret generic clickhouse-intercluster-communications \
    --from-literal=secret="$(openssl rand -hex 32)" \
    --dry-run=client -o yaml | kubectl apply -f -
  note "✅ Created clickhouse-intercluster-communications"
else
  note "ℹ️ clickhouse-intercluster-communications already exists, reusing."
fi

wait_opaque_secret "${CLICKHOUSE_NS}" clickhouse-auth
wait_opaque_secret "${CLICKHOUSE_NS}" clickhouse-kafka-auth
wait_opaque_secret "${CLICKHOUSE_NS}" clickhouse-intercluster-communications

bold "🗄 Deploying ClickHouse (Keeper + CHI + Kafka ingest)..."
helm upgrade --install "${CLICKHOUSE_RELEASE}" "${SCRIPTDIR}/${CHART_CLICKHOUSE}" \
  -n "${CLICKHOUSE_NS}" \
  -f "${SCRIPTDIR}/${CHART_CLICKHOUSE}/values.yaml" \
  --set kafka.brokers="${KAFKA_BOOTSTRAP}"

bold "⏳ Waiting for ClickHouse Keeper pods to be ready..."
wait_pod_selector_ready "${CLICKHOUSE_NS}" "app=clickhouse-keeper" || true

bold "⏳ Waiting for ClickHouse CHI pods to be ready..."
wait_pod_selector_ready "${CLICKHOUSE_NS}" "clickhouse.altinity.com/chi=${CLICKHOUSE_CHI_NAME}"

#bold "⏳ Waiting for ClickHouse DDL queue to be ready..."
#wait_clickhouse_ddl_queue_ready

bold "⏳ Waiting for clickhouse-init job to complete..."
wait_job_complete "${CLICKHOUSE_NS}" "clickhouse-init" "1800s"

bold "✅ Verifying ClickHouse schema exists on ALL replicas (prevents intermittent UNKNOWN_DATABASE)..."
verify_clickhouse_schema_all_pods "${CLICKHOUSE_NS}" "${CLICKHOUSE_CHI_NAME}" "${CLICKHOUSE_DB_NAME}" "${CLICKHOUSE_DB_TABLE}"

note "✅ ClickHouse deployed and schema verified on all replicas."

# ------------------------ ClickHouse backup -------------------------------------
bold "🧰 Deploying ClickHouse backup CronJobs (daily + hourly + cleanup)..."
helm upgrade --install "${CLICKHOUSE_BACKUP_RELEASE}" "${SCRIPTDIR}/${CHART_CLICKHOUSE_BACKUP}" \
  -n "${CLICKHOUSE_NS}" \
  -f "${SCRIPTDIR}/${CHART_CLICKHOUSE_BACKUP}/values.yaml"

note "✅ ClickHouse backup CronJobs deployed."

# ------------------------ Grafana --------------------------------------------
bold "📦 Creating Kubernetes namespace: ${GRAFANA_NS}"
kubectl get ns "${GRAFANA_NS}" >/dev/null 2>&1 || kubectl create ns "${GRAFANA_NS}" --dry-run=client -o yaml | kubectl apply -f -
wait_ns "${GRAFANA_NS}"

bold "🔐 Ensuring Grafana admin secret (grafana-admin)..."
if ! kubectl -n "${GRAFANA_NS}" get secret grafana-admin >/dev/null 2>&1; then
  GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
  GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 24)}"
  kubectl -n "${GRAFANA_NS}" create secret generic grafana-admin \
    --from-literal=admin-user="${GRAFANA_ADMIN_USER}" \
    --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
  note "✅ Created grafana-admin (user=${GRAFANA_ADMIN_USER})."
  note "ℹ️ Password is stored in secret/grafana-admin (admin-password)."
else
  note "ℹ️ grafana-admin already exists, reusing."
fi

bold "🔐 Creating/refreshing Grafana ClickHouse auth secret (grafana-clickhouse-auth)..."
CH_USER="$(kubectl -n "${CLICKHOUSE_NS}" get secret clickhouse-auth -o jsonpath='{.data.username}' | base64 -d)"
CH_PASS="$(kubectl -n "${CLICKHOUSE_NS}" get secret clickhouse-auth -o jsonpath='{.data.password}' | base64 -d)"
kubectl -n "${GRAFANA_NS}" create secret generic grafana-clickhouse-auth \
  --from-literal=username="${CH_USER}" \
  --from-literal=password="${CH_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

bold "📊 Deploying Grafana (seed dashboards once, then disable provisioning)..."

helm upgrade --install "${GRAFANA_RELEASE}" "${SCRIPTDIR}/${CHART_GRAFANA}" \
  -n "${GRAFANA_NS}" -f "${SCRIPTDIR}/${CHART_GRAFANA}/values.yaml"

bold "⏳ Waiting for Grafana to be ready..."
wait_deploy_ready "${GRAFANA_NS}" "grafana" || true
wait_service "${GRAFANA_NS}" "grafana" || true

note "✅ Grafana deployed."

# --------------------------------- Summary ------------------------------------
cat <<EOF
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
✅ Deployment complete!
📌 Kafka pods: kubectl get pods -n ${KAFKA_NS}
📌 Kafka UI credentials: kafka-ui/values.yaml auth.uiLogin.username and auth.uiLogin.password
📌 Longhorn UI credentials: longhorn-ui-ingress/values.yaml auth.username and auth.password
📌 Headlamp access: kubectl create token headlamp-admin -n ${HEADLAMP_NS}
📌 Kafka bootstrap for bridge: ${KAFKA_BOOTSTRAP}
📌 Grafana: http://$(yq e '.ingress.host' "${SCRIPTDIR}/${CHART_GRAFANA}/values.yaml")
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
🩺 Checks you can run:
  kubectl -n ${KAFKA_NS} get kafkatopics.kafka.strimzi.io | grep mqtt.raw || true
EOF


cat <<EOF
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
🩺 ClickHouse sanity checks:

# 1) Pods / services
kubectl -n ${CLICKHOUSE_NS} get pods -o wide
kubectl -n ${CLICKHOUSE_NS} get svc

# 2) Basic SQL health + tables present
export CH_USER="\$(kubectl -n ${CLICKHOUSE_NS} get secret clickhouse-auth -o jsonpath='{.data.username}' | base64 -d)"
export CH_PASS="\$(kubectl -n ${CLICKHOUSE_NS} get secret clickhouse-auth -o jsonpath='{.data.password}' | base64 -d)"
export CH_POD="\$(kubectl -n ${CLICKHOUSE_NS} get pod -l clickhouse.altinity.com/chi=clickhouse -o jsonpath='{.items[0].metadata.name}')"

kubectl -n ${CLICKHOUSE_NS} exec -it "\$CH_POD" -- clickhouse-client \
  -u "\$CH_USER" --password "\$CH_PASS" --query "
  SELECT version();
  SELECT hostName() AS host, uptime() AS uptime_s;
  SELECT cluster, shard_num, replica_num, host_name, host_address
  FROM system.clusters
  ORDER BY cluster, shard_num, replica_num;
  SELECT database, name, engine
  FROM system.tables
  WHERE database IN ('\${CLICKHOUSE_DB:-envsensor}', 'envsensor')
  ORDER BY database, name;
"

# 3) Do we have recent data landing in MergeTree?
kubectl -n ${CLICKHOUSE_NS} exec -it "\$CH_POD" -- clickhouse-client \
  -u "\$CH_USER" --password "\$CH_PASS" --query "
  SELECT
    count() AS rows,
    min(time) AS min_time,
    max(time) AS max_time
  FROM envsensor.enriched_readings;
"

# 4) Get 10 newest messages
kubectl -n ${CLICKHOUSE_NS} exec -it "\$CH_POD" -- clickhouse-client \
  -u "\$CH_USER" --password "\$CH_PASS" --query "
  SELECT
  time,
  topic,
  if(length(ipv4) = 4,
     IPv4NumToString(byteSwap(reinterpretAsUInt32(toFixedString(ipv4, 4)))),
     NULL) AS ipv4,
  if(length(ipv6) = 16,
     IPv6NumToString(toFixedString(ipv6, 16)),
     NULL) AS ipv6,
  user,
  clientid,
  broker,
  lower(MACNumToString(mac)) AS mac,
  bme280_t, bme280_p, bme280_h,
  tmp117_t,
  aht20_t, aht20_h,
  sht41_t, sht41_h
FROM envsensor.enriched_readings
ORDER BY time DESC
LIMIT 10;
"

# 5) Most recent measurement
kubectl -n ${CLICKHOUSE_NS} exec -it "\$CH_POD" -- clickhouse-client \
  -u "\$CH_USER" --password "\$CH_PASS" --query "
  WITH
    formatDateTime(time, '%FT%T', 'UTC') AS sec_utc,
    lpad(toString(toUnixTimestamp64Nano(time) % 1000000000), 9, '0') AS nanos
  SELECT
    concat(sec_utc, '.', nanos, 'Z') AS time,
    bme280_t,
    aht20_t,
    sht41_t,
    tmp117_t,
    bme280_h,
    aht20_h,
    sht41_h,
    bme280_p
  FROM envsensor.enriched_readings
  ORDER BY time DESC
  LIMIT 1;
"
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EOF
