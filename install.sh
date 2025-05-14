#!/bin/bash

set -e  # Exit on error

SCRIPTDIR="$(dirname "$0")"
NAMESPACE="$(yq e '.namespace' ${SCRIPTDIR}/kafka-deployment/values.yaml)"

echo "📦 Creating Kubernetes namespace for Kafka..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "💾 Deploying Kafka Local Storage (PVs & StorageClass)..."
helm upgrade --install kafka-local-storage ./kafka-local-storage -n $NAMESPACE

echo "⏳ Waiting for PersistentVolumes to be created..."
kubectl wait pv $(yq '.persistentVolumes[].name' ${SCRIPTDIR}/kafka-local-storage/values.yaml | xargs) --for=jsonpath='{.status.phase}'=Available --timeout=60s || true

echo "👷 Installing Strimzi Kafka Operator..."
helm repo add strimzi https://strimzi.io/charts/
helm repo update
helm upgrade --install strimzi-operator strimzi/strimzi-kafka-operator -n $NAMESPACE -f $(dirname "$0")/kafka-deployment/operator-values.yaml

echo "⏳ Waiting for Strimzi Operator to be ready..."
kubectl wait --for=condition=Available deployment/strimzi-cluster-operator -n $NAMESPACE --timeout=120s || true

echo "🚀 Deploying Kafka with Strimzi..."
helm upgrade --install kafka-cluster ./kafka-deployment -n $NAMESPACE -f $(dirname "$0")/kafka-deployment/values.yaml

echo "⏳ Waiting for Kafka bootstrap service to be ready..."
kubectl wait --for=condition=ready pod -l strimzi.io/cluster=kafka-cluster,strimzi.io/kind=Kafka -n kafka --timeout=180s || true
kubectl wait --for=jsonpath='{.spec.clusterIP}' service/kafka-cluster-kafka-bootstrap -n kafka --timeout=120s || true

echo "🎛 Deploying Kafka UI..."
helm upgrade --install kafka-ui ./kafka-ui -n $NAMESPACE -f $(dirname "$0")/kafka-ui/values.yaml

echo "⏳ Waiting for Kafka UI service to be ready..."
kubectl wait --for=condition=ready pod -l app=kafka-ui -n kafka --timeout=120s || true
kubectl wait --for=jsonpath='{.spec.clusterIP}' service/kafka-ui -n kafka --timeout=30s || true

echo "✅ Deployment completed!"
echo "📌 Check the Kafka pods using: kubectl get pods -n $NAMESPACE"
