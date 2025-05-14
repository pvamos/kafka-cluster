#!/bin/bash

set -e  # Exit on error

SCRIPTDIR="$(dirname "$0")"
NAMESPACE="$(yq e '.namespace' ${SCRIPTDIR}/kafka-deployment/values.yaml)"

echo "📦 Creating Kubernetes namespace for Kafka..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo "💾 Deploying Kafka Local Storage (PVs & StorageClass)..."
helm upgrade --install kafka-local-storage ./kafka-local-storage -n ${NAMESPACE}

echo "⏳ Waiting for PersistentVolumes to be created..."
time kubectl wait pv $(yq '.persistentVolumes[].name' ${SCRIPTDIR}/kafka-local-storage/values.yaml | xargs) --for=jsonpath='{.status.phase}'=Available --timeout=600s || true

echo "👷 Installing Strimzi Kafka Operator..."
helm repo add strimzi https://strimzi.io/charts/
helm repo update
helm upgrade --install strimzi-operator strimzi/strimzi-kafka-operator -n ${NAMESPACE} -f ${SCRIPTDIR}/kafka-deployment/operator-values.yaml

echo "⏳ Waiting for Strimzi Operator to be ready..."
time kubectl wait --for=condition=Available deployment/strimzi-cluster-operator -n ${NAMESPACE} --timeout=600s || true

echo "🚀 Deploying Kafka with Strimzi..."
helm upgrade --install kafka-cluster ./kafka-deployment -n ${NAMESPACE} -f ${SCRIPTDIR}/kafka-deployment/values.yaml

echo "⏳ Waiting for Kafka bootstrap service to be ready..."
for i in {1..30}; do
  if kubectl get svc kafka-cluster-kafka-bootstrap -n ${NAMESPACE} >/dev/null 2>&1; then
    echo "✅ kafka-cluster-kafka-bootstrap service is available. Waiting 5 seconds..."
    sleep 5
	break
  fi
  echo "⏳ Service not ready yet. Waiting 5 seconds..."
  sleep 5
done
time kubectl wait --for=condition=Ready pod -l strimzi.io/broker-role=true -n ${NAMESPACE} --timeout=600s || true
time kubectl wait --for=jsonpath='{.spec.clusterIP}' service/kafka-cluster-kafka-bootstrap -n ${NAMESPACE} --timeout=600s || true

echo "🎛 Deploying Kafka UI..."
helm upgrade --install kafka-ui ./kafka-ui -n ${NAMESPACE} -f ${SCRIPTDIR}/kafka-ui/values.yaml

echo "⏳ Waiting for Kafka UI service to be ready..."
time kubectl wait --for=condition=ready pod -l app=kafka-ui -n ${NAMESPACE} --timeout=600s || true
time kubectl wait --for=jsonpath='{.spec.clusterIP}' service/kafka-ui -n ${NAMESPACE} --timeout=600s || true

echo "✅ Deployment completed!"
echo "📌 Check the Kafka pods using: kubectl get pods -n ${NAMESPACE}"
