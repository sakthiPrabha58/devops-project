# Runbook — No Ansible Worker

## 1. Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Save the outputs:

```bash
terraform output
```

## 2. Ansible inventory

Create:

```bash
cd ../ansible
cp inventory/hosts.ini.example inventory/hosts.ini
nano inventory/hosts.ini
```

Use Terraform outputs for the IP addresses. Do not add an `ANSIBLE_WORKER_IP`.

Set your real private-key path in `ansible.cfg`.

Test:

```bash
ansible all -m ping
```

## 3. Configure operating systems and services

```bash
ansible-playbook site.yml
```

This configures common packages and Docker everywhere, Java/Maven where required, Jenkins on the Jenkins node, Nexus on the Nexus node, and Kubernetes packages on cluster nodes.

## 4. Create Kubernetes cluster

```bash
ansible-playbook kubernetes.yml
```

Verify on the control plane:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Expected worker roles include `jenkins`, `maven`, `nexus`, and `web`. There is no `ansible` worker.

## 5. Jenkins kubeconfig

On the control plane, obtain `/home/ubuntu/.kube/config` securely and add it to Jenkins:

**Manage Jenkins → Credentials → Global → Add Credentials**

- Kind: Secret file
- ID: `kubeconfig`

Never commit this file.

## 6. Nexus

Open Nexus on the Nexus node and configure:

- Maven hosted repository: `maven-releases` on port 8081.
- Docker hosted repository: port 8082.

For production, use TLS and restrict administrative access.

## 7. Jenkins credentials

Create:

- `nexus-host` — Secret text containing the Nexus private IP/DNS reachable by Jenkins.
- `nexus-docker` — Username/password for Nexus Docker registry.
- `kubeconfig` — Secret file containing the Kubernetes admin kubeconfig.

## 8. Jenkins pipeline

Create a Pipeline job and use the repository's `jenkins/Jenkinsfile`.

The pipeline runs:

```text
Checkout
→ Maven clean test package
→ Nexus Maven deploy
→ Docker build
→ Nexus Docker push
→ kubectl deployment
```

The deploy stage runs on the Jenkins controller, not an Ansible worker.

## 9. Kubernetes application secret

On a secure machine:

```bash
cd kubernetes
cp secret.yaml.example secret.yaml
nano secret.yaml
```

Set the RDS username/password and apply it:

```bash
kubectl apply -f secret.yaml
```

Do not commit `secret.yaml`.

## 10. Verify application

```bash
kubectl -n devshop get pods
kubectl -n devshop get svc
kubectl -n devshop rollout status deployment/devshop
```

Then open the Terraform `application_url` output.

Health endpoint:

```text
/api/health
```

## 11. Troubleshooting

```bash
kubectl -n devshop get pods -o wide
kubectl -n devshop describe pod <pod-name>
kubectl -n devshop logs deployment/devshop
kubectl get nodes -o wide
```

For RDS connectivity, verify that the RDS security group allows TCP 3306 from the Kubernetes security group and that the application JDBC URL is:

```text
jdbc:mysql://<RDS_ENDPOINT>:3306/devshop
```
