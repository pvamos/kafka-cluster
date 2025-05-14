# Kafka cluster deployment with Helm & Strimzi

This project deploys a **Kafka cluster** on **Kubernetes** using **Strimzi**, **Helm**, and includes **Kafka UI** for topic/consumer group management.

## 👨‍🔬 Author

**Péter Vámos**

* [https://linkedin.com/in/pvamos](https://linkedin.com/in/pvamos)
* [pvamos@gmail.com](mailto:pvamos@gmail.com)

## 📜 Overview

This setup includes:

* ✅ **Strimzi Kafka Operator** for managing Kafka
* ✅ **4-node Kafka cluster** (Kafka brokers run only on dedicated nodes)
* ✅ **Local PersistentVolumes (PVs) for Kafka storage**
* ✅ **Kafka UI** with SCRAM authentication and optional login screen
* ✅ **Automated Helm deployment script (`install.sh`)**

## 📜 Summary

* ✅ Kafka brokers run only on Kafka nodes (`node-role.kubernetes.io/kafka=true`)
* ✅ Kafka storage uses local PVs (45Gi from `/var/lib/kafka`)
* ✅ Kafka controllers run on control-plane nodes using Longhorn
* ✅ Kafka runs in **KRaft mode** (no Zookeeper)
* ✅ Kafka UI is deployed with Strimzi-compatible SCRAM credentials

## 🚀 Deployment steps

### 1️⃣  Clone the repository

```sh
git clone <repository-url>
cd kafka-cluster
chmod +x install.sh
```

### 2️⃣  Run the installation script

```sh
./install.sh
```

### 3️⃣  Verify the deployment

```sh
kubectl get pods -n kafka [ -o wide ]
```

Expected output:
```
NAME       STATUS   ROLES                       AGE     VERSION
control1   Ready    control-plane,etcd,master   1h48m   v1.32.4+k3s1
control2   Ready    control-plane,etcd,master   1h47m   v1.32.4+k3s1
control3   Ready    control-plane,etcd,master   1h47m   v1.32.4+k3s1
worker1    Ready    kafka,worker                1h47m   v1.32.4+k3s1
worker2    Ready    kafka,worker                1h47m   v1.32.4+k3s1
worker3    Ready    kafka,worker                1h47m   v1.32.4+k3s1
worker4    Ready    kafka,worker                1h47m   v1.32.4+k3s1
```

## 📁 Project directory structure

```
kafka-cluster/
|
├── kafka-local-storage/         # Helm chart for Kafka local storage
│   ├── templates/
│   │   ├── storageclass.yaml
│   │   └── pv.yaml
│   ├── Chart.yaml
│   └── values.yaml
|
├── kafka-deployment/            # Helm chart for Kafka (Strimzi)
│   ├── templates/
│   │   ├── kafka-cluster.yaml
│   │   ├── kafka-pvc.yaml
│   │   ├── kafka-topics.yaml
│   │   ├── kafka-users.yaml
│   │   └── kafka-nodepools.yaml
│   ├── Chart.yaml
│   └── values.yaml
|
├── kafka-ui/                    # Helm chart for Kafka UI
│   ├── templates/
│   │   ├── kafka-user.yaml
│   │   └── kafka-ui-deployment.yaml
│   ├── Chart.yaml
│   └── values.yaml
|
├── install.sh                   # Helm automation script
├── LICENSE                      # MIT License
└── README.md                    # This documentation
```

## ⚘ Helm chart components

### Kafka local storage (`kafka-local-storage/`)

* `pv.yaml`: Defines local PersistentVolumes per node
* `storageclass.yaml`: StorageClass for PV provisioning

### Kafka cluster (`kafka-deployment/`)

* `kafka-cluster.yaml`: Main Strimzi Kafka resource
* `kafka-nodepools.yaml`: Broker and controller node pools
* `kafka-users.yaml`: Defines SCRAM-authenticated users
* `kafka-topics.yaml`: Defines auto-created topics

### Kafka UI (`kafka-ui/`)

* `kafka-user.yaml`: Creates the SCRAM user
* `kafka-ui-deployment.yaml`: Deploys Kafka UI using `sasl.jaas.config` from secret

## 📌 Troubleshooting

### Check logs

```sh
kubectl logs -n kafka -l app.kubernetes.io/name=kafka
```

### Delete and reinstall Kafka

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
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### Access Kafka UI

```sh
kubectl port-forward svc/kafka-ui -n kafka 8080:8080
```

Visit [http://localhost:8080](http://localhost:8080)

## ⚖ License

MIT License

Copyright (c) 2025 **Péter Vámos**

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

