# Kafka cluster seployment with Helm & Strimzi

This project deploys a **Kafka cluster** on **Kubernetes** using **Strimzi** and **Helm**.

## Author

Péter Vámos
- https://linkedin.com/in/pvamos
- pvamos@gmail.com

## 📜 Overview

This setup includes:
- ✅ **Strimzi Kafka Operator** for managing Kafka
- ✅ **4-node Kafka cluster** (Kafka brokers run only on dedicated nodes)
- ✅ **3-node Zookeeper cluster** (runs only on worker nodes)
- ✅ **Local PersistentVolumes (PVs) for Kafka storage**
- ✅ **Automated Helm deployment script (`install.sh`)**

## 📜 Summary
- ✅ Kafka brokers run only on Kafka nodes (node-role.kubernetes.io/kafka=true)
- ✅ Kafka storage uses local persistent volumes (28Gi from /var/lib/kafka)
- ✅ Zookeeper runs only on worker nodes (node-role.kubernetes.io/worker=true)
- ✅ Strimzi Operator manages Kafka automatically
- ✅ Strimzi uses `template.pod` for scheduling rules, not `nodeAffinity` directly inside `spec.kafka`.

## 🚀 Deployment steps

### 1️⃣ Clone the repository
```sh
git clone <repository-url>
cd kafka-cluster
chmod +x install.sh
```

### 2️⃣ Run the installation script
```sh
./install.sh
```

### 3️⃣ Verify the deployment
```sh
kubectl get pods -n kafka -o wide
```

Expected output:
```
NAME                          READY   STATUS    NODE
kafka-cluster-kafka-0         1/1     Running   kafka1
kafka-cluster-kafka-1         1/1     Running   kafka2
kafka-cluster-kafka-2         1/1     Running   kafka3
kafka-cluster-kafka-3         1/1     Running   kafka4
kafka-cluster-zookeeper-0     1/1     Running   workerX
kafka-cluster-zookeeper-1     1/1     Running   workerY
kafka-cluster-zookeeper-2     1/1     Running   workerZ
```

## Project directory structure
```
kafka-cluster/
│
├── kafka-local-storage/          # Helm chart for Kafka local storage (PVs & StorageClass)
│   ├── templates/                # Templates for Kubernetes resources
│   │   ├── storageclass.yaml     # Defines the StorageClass for Kafka
│   │   ├── pv.yaml               # Defines PersistentVolumes for Kafka nodes
│   ├── Chart.yaml                # Helm chart metadata
│   ├── values.yaml               # Configurable values for storage (size, nodes, etc.)
│
├── kafka-deployment/             # Helm chart for Kafka deployment with Strimzi
│   ├── templates/                # Templates for Kubernetes resources
│   │   ├── kafka-cluster.yaml    # Defines Kafka and Zookeeper cluster
│   │   ├── kafka-pvc.yaml        # Defines Kafka PersistentVolumeClaims (PVCs)
│   ├── Chart.yaml                # Helm chart metadata
│   ├── values.yaml               # Configurable values for Kafka/Zookeeper
│
├── install.sh                    # Shell script to automate Helm chart installation
├── LICENSE                       # MIT License
└── README.md                     # Documentation for deployment
```

## 📌 Troubleshooting

### 🔍 Check logs

```sh
kubectl logs -n kafka -l app.kubernetes.io/name=kafka
```

### ❌ Delete and re-install Kafka
```sh
helm uninstall kafka-cluster -n kafka
helm uninstall strimzi-operator -n kafka
kubectl delete namespace kafka
./install.sh
```

---

Copyright (c) 2025 Péter Vámos

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

