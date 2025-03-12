# Kafka Cluster Deployment with Helm & Strimzi

This project deploys a **Kafka cluster** on **Kubernetes** using **Strimzi** and **Helm**.

## 👨🏻‍🔬 Author

**Péter Vámos**  
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
- ✅ Kafka brokers run only on Kafka nodes (`node-role.kubernetes.io/kafka=true`)
- ✅ Kafka storage uses local persistent volumes (28Gi from `/var/lib/kafka`)
- ✅ Zookeeper runs only on worker nodes (`node-role.kubernetes.io/worker=true`)
- ✅ Strimzi Operator manages Kafka automatically
- ✅ Strimzi uses `template.pod` for scheduling rules, not `nodeAffinity` directly inside `spec.kafka`.

## 🚀 Deployment Steps

### 1️⃣ Clone the Repository
```sh
git clone <repository-url>
cd kafka-cluster
chmod +x install.sh
```

### 2️⃣ Run the Installation Script
```sh
./install.sh
```

### 3️⃣ Verify the Deployment
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

## 📁 Project Directory Structure
```
kafka-cluster/
│
├── kafka-local-storage/          # Helm chart for Kafka local storage (PVs & StorageClass)
│   ├── templates/                # Templates for Kubernetes resources
│   │   ├── storageclass.yaml     # Defines the StorageClass for Kafka
│   │   └── pv.yaml               # Defines PersistentVolumes for Kafka nodes
│   ├── Chart.yaml                # Helm chart metadata
│   └── values.yaml               # Configurable values for storage (size, nodes, etc.)
│
├── kafka-deployment/             # Helm chart for Kafka deployment with Strimzi
│   ├── templates/                # Templates for Kubernetes resources
│   │   ├── kafka-cluster.yaml    # Defines Kafka and Zookeeper cluster
│   │   ├── kafka-pvc.yaml        # Defines Kafka PersistentVolumeClaims (PVCs)
│   │   ├── kafka-topics.yaml     # Defines Kafka topics
│   │   ├── kafka-users.yaml      # Defines Kafka user authentication and ACLs
│   │   ├── storageclass-zookeeper.yaml # Defines the StorageClass for Zookeeper
│   ├── Chart.yaml                # Helm chart metadata
│   └── values.yaml               # Configurable values for Kafka/Zookeeper
│
├── install.sh                    # Shell script to automate Helm chart installation
├── LICENSE                       # MIT License
└── README.md                     # Documentation for deployment
```

## ⎈ Helm chart components

### 🖴 Kafka local storage
The `kafka-local-storage` chart defines the local PersistentVolumes (PVs) and StorageClass for Kafka. 

- `storageclass.yaml`: Defines a local storage class (`kafka-local`)
- `pv.yaml`: Defines PersistentVolumes for Kafka storage

### 💡Kafka deployment
The `kafka-deployment` chart deploys Kafka and Zookeeper using Strimzi.

- `kafka-cluster.yaml`: Defines the Kafka cluster and Zookeeper settings
- `kafka-pvc.yaml`: Configures the PersistentVolumeClaims (PVCs) for Kafka
- `kafka-topics.yaml`: Pre-defines Kafka topics with retention policies
- `kafka-users.yaml`: Configures Kafka authentication and user ACLs
- `storageclass-zookeeper.yaml`: Defines the StorageClass for Zookeeper

## 📌 Troubleshooting

### 🔍 Check Logs

```sh
kubectl logs -n kafka -l app.kubernetes.io/name=kafka
```

### ❌ Delete and reinstall Kafka
```sh
helm uninstall kafka-cluster -n kafka
helm uninstall strimzi-operator -n kafka
kubectl delete namespace kafka
./install.sh
```

## ⌨ Useful commands

### Get Kafka brokers
```sh
kubectl get pods -n kafka -l strimzi.io/kind=Kafka
```

### Get Kafka topics
```sh
kubectl get kafkatopics -n kafka
```

### Describe Kafka topics
```sh
kubectl describe kafkatopic <topic-name> -n kafka
```

### Get Kafka users
```sh
kubectl get kafkausers -n kafka
```

### Access Kafka via CLI
```sh
kubectl exec -it <kafka-broker-pod> -n kafka -- /bin/sh
```

Once inside the pod:
```sh
kafka-topics.sh --bootstrap-server localhost:9092 --list
```


## ⚖ License

MIT License  

Copyright (c) 2025 **Péter Vámos**  

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


