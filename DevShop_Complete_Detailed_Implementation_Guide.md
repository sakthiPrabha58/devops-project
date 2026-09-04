# DevShop DevOps Project — Detailed Hands-On Implementation Guide

## Purpose

This document expands the original process guide into an implementation manual. It explains **what to do, where to do it, what commands to run, what files to edit, how to verify the result, and what to check when a step fails**.

The architecture intentionally has **NO Ansible worker**.

Architecture:

```text
Developer
   |
 GitHub
   |
Webhook
   v
Jenkins
   |---- Maven build/test
   |---- Nexus Maven publish
   |---- Docker build
   |---- Nexus Docker push
   |---- kubectl deployment
   v
Kubernetes
   |
DevShop Pods
   |
Service / NodePort
   |
AWS ALB
   |
Route53
   |
User

Terraform -> creates AWS infrastructure
Ansible Server -> configures EC2 servers over SSH
RDS -> MySQL database
S3 -> object storage
IAM + Security Groups + Kubernetes Secrets -> security
```

---

# PART 1 — UNDERSTAND THE TARGET ARCHITECTURE

## 1. Servers and their jobs

Use these logical server roles:

```text
terraform-server
ansible-server
k8s-control-plane
jenkins-worker
maven-worker
nexus-worker
web-worker
```

There must NOT be:

```text
ansible-worker
```

The Ansible server is the Ansible control node. Ansible is agentless and connects to managed EC2 instances through SSH.

Jenkins performs CI/CD and deploys to Kubernetes directly with `kubectl`.

---

# PART 2 — PREPARE YOUR WORK MACHINE

## 2. Install the required tools

The machine from which you initially run Terraform and Ansible should have:

```text
Git
AWS CLI
Terraform
Ansible
OpenSSH
```

Check them:

```bash
git --version
aws --version
terraform version
ansible --version
ssh -V
```

If a command is missing, install that tool before continuing.

---

## 3. Create an SSH key

If you already have an AWS EC2 key pair, use that key.

Example local key:

```text
~/.ssh/devshop.pem
```

Protect it:

```bash
chmod 400 ~/.ssh/devshop.pem
```

Do not commit this file to GitHub.

---

# PART 3 — DOWNLOAD AND INSPECT THE PROJECT

## 4. Extract the project

Example:

```bash
unzip devshop-devops-project-no-ansible-worker.zip
cd devshop-devops
```

Inspect the project:

```bash
find . -maxdepth 3 -type f | sort
```

Expected major areas:

```text
application/
terraform/
ansible/
kubernetes/
jenkins/
scripts/
docs/
```

If your project uses different directory names, use the actual names supplied by the project.

---

# PART 4 — VERIFY THE SPRING BOOT APPLICATION FIRST

Do this before troubleshooting AWS.

## 5. Enter the application

```bash
cd application
```

Check:

```bash
ls
```

You should find files similar to:

```text
pom.xml
Dockerfile
src/
```

---

## 6. Check Java

```bash
java -version
```

The project targets Java 21.

You want Java 21 available.

If Java is not installed on Ubuntu:

```bash
sudo apt update
sudo apt install -y openjdk-21-jdk
```

Verify:

```bash
java -version
```

---

## 7. Check Maven

```bash
mvn -version
```

Confirm Maven is using Java 21.

If Maven is missing:

```bash
sudo apt update
sudo apt install -y maven
```

Then:

```bash
mvn -version
```

---

## 8. Build and test

From the application directory:

```bash
mvn clean test package
```

Do not continue until this succeeds.

Check the JAR:

```bash
ls -lh target/
```

You should see the generated application JAR.

---

## 9. Run the application locally

Example:

```bash
java -jar target/devshop-1.0.0.jar
```

The application normally listens on:

```text
8080
```

Test from the same machine:

```bash
curl http://localhost:8080
```

If the project exposes a health endpoint, also test the configured health URL.

Stop it:

```text
Ctrl+C
```

### If Maven fails

Check:

```bash
java -version
mvn -version
```

Then run:

```bash
mvn clean test
```

Read the first meaningful compilation/test error rather than only the final `BUILD FAILURE` line.

---

# PART 5 — CONFIGURE AWS CLI

## 10. Configure credentials

Run:

```bash
aws configure
```

Enter:

```text
AWS Access Key ID: <your access key>
AWS Secret Access Key: <your secret>
Default region name: ap-south-1
Default output format: json
```

Verify:

```bash
aws sts get-caller-identity
```

A successful response contains your AWS account and identity information.

Never put AWS access keys in:

```text
*.tf
*.tfvars
Jenkinsfile
GitHub repository
Kubernetes manifests
```

---

# PART 6 — TERRAFORM CONFIGURATION

## 11. Enter Terraform

```bash
cd ../terraform
```

Inspect:

```bash
ls -la
```

Look for:

```text
main.tf
variables.tf
outputs.tf
*.tf
terraform.tfvars.example
```

Use the project's actual files.

---

## 12. Create your variable file

If supplied:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open it:

```bash
nano terraform.tfvars
```

Example values:

```hcl
aws_region  = "ap-south-1"
project_name = "devshop"
environment = "dev"

key_name = "YOUR_EC2_KEY_PAIR"

admin_cidr = "YOUR_PUBLIC_IP/32"

worker_count = 4

rds_username = "devshop"
rds_password = "USE_A_STRONG_PASSWORD"
rds_db_name = "devshop"
```

Important:

**Do not blindly copy these variable names if your `variables.tf` uses different names.**

Check:

```bash
grep -R "variable " -n *.tf
```

Then make sure every variable in `terraform.tfvars` actually exists.

---

## 13. Find your public IP

You need your public IP when the security groups restrict SSH.

For example:

```bash
curl -4 ifconfig.me
```

If it returns:

```text
203.0.113.10
```

use:

```text
203.0.113.10/32
```

Do not use:

```text
203.0.113.10
```

for a CIDR variable that expects `/32`.

---

## 14. Initialize Terraform

Run:

```bash
terraform init
```

Terraform downloads providers and initializes the working directory.

Expected result includes:

```text
Terraform has been successfully initialized!
```

---

## 15. Format Terraform

```bash
terraform fmt -recursive
```

Then check:

```bash
terraform fmt -check -recursive
```

---

## 16. Validate Terraform

```bash
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

If validation fails, fix the exact syntax/reference error before applying.

---

# PART 7 — REVIEW THE TERRAFORM PLAN

## 17. Generate the plan

```bash
terraform plan
```

Read the resources carefully.

You should expect infrastructure such as:

```text
VPC
Subnets
Route tables
Internet Gateway
NAT Gateway
Security Groups
IAM
EC2
RDS
S3
ALB
Route53
```

---

## 18. Verify NO Ansible worker

This is a mandatory architecture check.

Search Terraform files:

```bash
grep -Rni "ansible-worker" .
```

Also inspect the plan:

```bash
terraform plan | grep -i ansible
```

There must not be an EC2 resource intended to be an `ansible-worker`.

The correct design is:

```text
Ansible Server
      |
      +---- SSH ----> Jenkins
      +---- SSH ----> Maven
      +---- SSH ----> Nexus
      +---- SSH ----> Kubernetes
```

---

# PART 8 — CREATE AWS INFRASTRUCTURE

## 19. Apply Terraform

Run:

```bash
terraform apply
```

Terraform displays the plan.

Enter:

```text
yes
```

Wait until completion.

---

## 20. Save Terraform outputs

Run:

```bash
terraform output
```

Record:

```text
Terraform server IP
Ansible server IP
Kubernetes control-plane IP
Worker IPs
Nexus address
RDS endpoint
ALB DNS name
S3 bucket
Route53 information
```

If an output is sensitive, do not post it publicly.

---

# PART 9 — TEST SSH TO EVERY IMPORTANT SERVER

## 21. Connect to Ansible server

Example:

```bash
ssh -i ~/.ssh/devshop.pem ubuntu@ANSIBLE_SERVER_IP
```

If Ubuntu uses another username, use the username created by the AMI.

---

## 22. Test each server

From your machine:

```bash
ssh -i ~/.ssh/devshop.pem ubuntu@JENKINS_IP
ssh -i ~/.ssh/devshop.pem ubuntu@MAVEN_IP
ssh -i ~/.ssh/devshop.pem ubuntu@NEXUS_IP
ssh -i ~/.ssh/devshop.pem ubuntu@K8S_CONTROL_PLANE_IP
```

If workers have public addresses, test those too.

---

## 23. SSH troubleshooting

If:

```text
Permission denied (publickey)
```

check:

```text
Correct private key
Correct EC2 username
Correct key pair
```

If:

```text
Connection timed out
```

check:

```text
EC2 running
Security group port 22
Source IP allowed
Route table
Public/private addressing
Internet/NAT design
```

Do not troubleshoot Ansible until normal SSH works.

---

# PART 10 — CONFIGURE ANSIBLE

## 24. Enter the Ansible directory

On the Ansible server:

```bash
cd ~/ansible
```

If the project is not there, clone/copy the repository first.

Example:

```bash
git clone YOUR_GITHUB_REPOSITORY
cd YOUR_REPOSITORY/ansible
```

---

## 25. Create the inventory

If provided:

```bash
cp inventory/hosts.ini.example inventory/hosts.ini
```

Edit:

```bash
nano inventory/hosts.ini
```

Use the actual private/public addresses appropriate for your network.

Example structure:

```ini
[terraform]
TERRAFORM_HOST ansible_host=TERRAFORM_IP node_role=terraform

[ansible]
ANSIBLE_HOST ansible_host=ANSIBLE_IP node_role=ansible

[kube_control_plane]
K8S_CONTROL_HOST ansible_host=K8S_CONTROL_IP node_role=control-plane

[kube_workers]
JENKINS_HOST ansible_host=JENKINS_IP node_role=jenkins
MAVEN_HOST ansible_host=MAVEN_IP node_role=maven
NEXUS_HOST ansible_host=NEXUS_IP node_role=nexus
WEB_HOST ansible_host=WEB_IP node_role=web
```

Do NOT create:

```ini
[ansible_worker]
```

or:

```ini
ANSIBLE_WORKER
```

---

## 26. Configure SSH settings

Open:

```bash
nano ansible.cfg
```

Example:

```ini
[defaults]
inventory = inventory/hosts.ini
private_key_file = ~/.ssh/devshop.pem
host_key_checking = False
interpreter_python = auto_silent
```

Use the real key location.

---

## 27. Test inventory parsing

Run:

```bash
ansible-inventory --graph
```

You should see your groups.

You should NOT see an Ansible worker.

---

## 28. Test Ansible connectivity

Run:

```bash
ansible all -m ping
```

Successful hosts should return:

```text
pong
```

If only one host fails:

```bash
ansible FAILED_HOST -m ping -vvv
```

Fix SSH/connectivity first.

---

# PART 11 — RUN SERVER CONFIGURATION

## 29. Inspect available playbooks

From the Ansible directory:

```bash
find . -maxdepth 3 -type f | sort
```

Look for:

```text
site.yml
playbook.yml
kubernetes.yml
roles/
```

Use the actual playbook names in the project.

---

## 30. Run the main playbook

If the project uses `site.yml`:

```bash
ansible-playbook site.yml
```

If it uses another main playbook, use that file.

---

## 31. Run with extra output when troubleshooting

```bash
ansible-playbook site.yml -vv
```

For very detailed troubleshooting:

```bash
ansible-playbook site.yml -vvv
```

Do not immediately jump to `-vvv`; first inspect the task that failed.

---

# PART 12 — INSTALL AND VERIFY DOCKER

## 32. Check Docker

On Jenkins and any machine requiring Docker:

```bash
docker --version
```

Then:

```bash
sudo systemctl status docker
```

If needed:

```bash
sudo systemctl enable --now docker
```

---

## 33. Test Docker

```bash
sudo docker run hello-world
```

If Jenkins needs Docker without `sudo`, check the Jenkins user:

```bash
groups jenkins
```

Add it if required:

```bash
sudo usermod -aG docker jenkins
```

Then restart the Jenkins service/session as appropriate:

```bash
sudo systemctl restart jenkins
```

Verify again from the Jenkins execution environment.

---

# PART 13 — JAVA AND MAVEN ON BUILD/JENKINS SERVER

## 34. Verify Java

```bash
java -version
```

Expected major version:

```text
21
```

---

## 35. Verify Maven

```bash
mvn -version
```

Then:

```bash
mvn clean test
```

If this fails, fix the build environment before configuring the pipeline.

---

# PART 14 — JENKINS INSTALLATION

## 36. Install Jenkins prerequisites

On the Jenkins server:

```bash
sudo apt update
sudo apt install -y openjdk-21-jdk curl ca-certificates gnupg
```

Verify:

```bash
java -version
```

---

## 37. Add Jenkins signing key

Create the keyring directory:

```bash
sudo mkdir -p /etc/apt/keyrings
```

Download the official key:

```bash
sudo curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key   -o /etc/apt/keyrings/jenkins-keyring.asc
```

Set permissions:

```bash
sudo chmod 644 /etc/apt/keyrings/jenkins-keyring.asc
```

---

## 38. Add Jenkins repository

Create:

```bash
sudo nano /etc/apt/sources.list.d/jenkins.list
```

Put the repository entry supplied by the Jenkins documentation/project configuration.

For the repository style used by the project:

```text
deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/
```

Then:

```bash
sudo apt update
```

If you receive:

```text
NO_PUBKEY
repository is not signed
```

check:

```bash
ls -l /etc/apt/keyrings/jenkins-keyring.asc
cat /etc/apt/sources.list.d/jenkins.list
```

Remove stale/duplicate Jenkins repository entries before retrying.

---

## 39. Install Jenkins

```bash
sudo apt install -y jenkins
```

Enable and start:

```bash
sudo systemctl enable --now jenkins
```

Check:

```bash
sudo systemctl status jenkins
```

---

## 40. Get initial Jenkins password

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Save it temporarily.

---

## 41. Open Jenkins

From your browser:

```text
http://JENKINS_IP:8080
```

Complete:

```text
Unlock Jenkins
Install plugins
Create admin user
Configure Jenkins URL
```

---

# PART 15 — NEXUS

## 42. Verify Nexus

On the Nexus server:

```bash
sudo systemctl status nexus
```

If Nexus runs in Docker:

```bash
docker ps
```

Check the configured Nexus UI port, commonly:

```text
8081
```

From Jenkins:

```bash
curl http://NEXUS_HOST:8081
```

---

## 43. Configure Nexus repositories

The project needs the repositories expected by the Jenkins pipeline.

Typical roles:

```text
Maven repository
Docker hosted repository
```

Do not assume the Docker port if the project specifies another port.

Check the actual Nexus configuration.

---

## 44. Test Docker registry connectivity

From Jenkins:

```bash
curl http://NEXUS_HOST:DOCKER_PORT
```

Then authenticate when the registry is configured:

```bash
docker login NEXUS_HOST:DOCKER_PORT
```

Use Nexus credentials.

---

# PART 16 — KUBERNETES

## 45. Verify Kubernetes packages

On the control plane and workers:

```bash
kubeadm version
kubelet --version
kubectl version --client
```

If Ubuntu says:

```text
No package matching 'kubelet' is available
```

do not repeatedly run `apt install kubelet`.

First inspect the Kubernetes apt repository:

```bash
grep -Rni "kubernetes" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null
```

Then:

```bash
sudo apt update
apt-cache policy kubelet kubeadm kubectl
```

If no candidate exists, the repository is missing or invalid.

---

## 46. Disable swap

On Kubernetes nodes:

```bash
sudo swapoff -a
```

Check:

```bash
free -h
```

Then ensure swap is disabled after reboot by updating `/etc/fstab` appropriately.

---

## 47. Configure container runtime

Verify the runtime required by the project's Kubernetes configuration.

For containerd:

```bash
sudo systemctl status containerd
```

Enable it:

```bash
sudo systemctl enable --now containerd
```

The exact runtime configuration must match the Kubernetes version/project manifests.

---

# PART 17 — INITIALIZE KUBERNETES CONTROL PLANE

## 48. Run the project's Kubernetes initialization

Use the supplied Ansible Kubernetes playbook.

Example:

```bash
ansible-playbook kubernetes.yml
```

The expected sequence is:

```text
Install Kubernetes packages
        |
Configure runtime
        |
Initialize control plane
        |
Install CNI
        |
Generate worker join command
        |
Join workers
```

---

## 49. Verify control plane

On the control plane:

```bash
kubectl get nodes
```

Then:

```bash
kubectl get pods -A
```

System pods should become healthy.

---

# PART 18 — JOIN WORKERS

## 50. Obtain the join command

On the control plane, if needed:

```bash
kubeadm token create --print-join-command
```

It returns a command similar to:

```bash
kubeadm join CONTROL_PLANE_IP:6443 --token ... --discovery-token-ca-cert-hash ...
```

Run the generated command on each worker.

If Ansible handles this, let the Ansible playbook perform the join.

---

## 51. Verify workers

On the control plane:

```bash
kubectl get nodes -o wide
```

All intended nodes should eventually show:

```text
Ready
```

There must be no:

```text
ansible-worker
```

---

# PART 19 — LABEL KUBERNETES NODES

## 52. First discover real node names

Run:

```bash
kubectl get nodes
```

Suppose it returns:

```text
ip-10-0-1-10
ip-10-0-2-20
ip-10-0-3-30
ip-10-0-4-40
```

Use these actual names.

Do NOT run:

```bash
kubectl label node JENKINS_NODE node-role=jenkins
```

unless the real node is literally named `JENKINS_NODE`.

---

## 53. Apply labels

Example:

```bash
kubectl label node ip-10-0-2-20 node-role=jenkins
kubectl label node ip-10-0-3-30 node-role=maven
kubectl label node ip-10-0-4-40 node-role=nexus
```

Use the labels required by the project's Deployment manifests.

Verify:

```bash
kubectl get nodes --show-labels
```

---

# PART 20 — RDS DATABASE

## 54. Get RDS endpoint

From Terraform:

```bash
terraform output
```

Find the endpoint.

It resembles:

```text
xxxxx.rds.amazonaws.com
```

---

## 55. Understand the JDBC URL

Spring Boot needs a JDBC URL.

Correct structure:

```text
jdbc:mysql://RDS_ENDPOINT:3306/DATABASE_NAME
```

Not merely:

```text
RDS_ENDPOINT
```

---

## 56. Check RDS status

Using AWS CLI:

```bash
aws rds describe-db-instances   --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address,Endpoint.Port]'   --output table
```

The database should be available.

---

## 57. Check security group

MySQL uses:

```text
TCP 3306
```

The RDS security group should allow connections from the application/Kubernetes network that needs them.

Do not make RDS publicly accessible just to solve connectivity problems.

---

## 58. Test MySQL connectivity

From an allowed machine:

```bash
mysql -h RDS_ENDPOINT -P 3306 -u USERNAME -p
```

If you get:

```text
ERROR 2003
Can't connect to MySQL server
```

check:

```text
RDS status
Correct endpoint
Port 3306
RDS security group
Source security group/IP
VPC
Subnet routing
Network ACL
DNS
```

A timeout usually indicates network access, not an incorrect password.

---

# PART 21 — KUBERNETES APPLICATION CONFIGURATION

## 59. Create namespace

Check:

```bash
kubectl get namespaces
```

If the project uses `devshop`:

```bash
kubectl create namespace devshop
```

Verify:

```bash
kubectl get namespace devshop
```

---

## 60. Create Secret

If supplied:

```bash
cd kubernetes
cp secret.yaml.example secret.yaml
```

Edit:

```bash
nano secret.yaml
```

Put required database credentials and other secrets into the Secret.

Apply:

```bash
kubectl apply -f secret.yaml
```

Verify only metadata:

```bash
kubectl -n devshop get secrets
```

Never commit the real Secret to GitHub.

---

## 61. Configure ConfigMap

Use ConfigMap for non-sensitive settings, such as:

```text
RDS hostname
Database name
Port
Application settings
```

Do not store passwords in ConfigMaps.

---

## 62. Create namespace declaratively when the project provides a manifest

If the project contains:

```text
namespace.yaml
```

prefer:

```bash
kubectl apply -f namespace.yaml
```

Use one consistent declarative workflow for resources managed by Git.

---

# PART 22 — DEPLOYMENT

## 63. Inspect the Deployment

Open:

```bash
nano deployment.yaml
```

Check:

```text
namespace
container image
containerPort
environment variables
Secret references
ConfigMap references
readinessProbe
livenessProbe
replicas
```

The image should reference the Nexus Docker registry when that is the project's design.

Example pattern:

```text
NEXUS_HOST:PORT/devshop:BUILD_NUMBER
```

---

## 64. Apply manifests

A typical order is:

```bash
kubectl apply -f namespace.yaml
kubectl apply -f secret.yaml
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

If the project has a different structure, use its manifests.

Then:

```bash
kubectl -n devshop get all
```

---

# PART 23 — SERVICE

## 65. Check Service

```bash
kubectl -n devshop get svc
```

Inspect details:

```bash
kubectl -n devshop describe svc devshop
```

Confirm:

```text
Service port
Target port
NodePort if used
Selector
Endpoints
```

Check endpoints:

```bash
kubectl -n devshop get endpoints
```

If there are no endpoints, the Service selector does not match the Pods or the Pods are not ready.

---

# PART 24 — ALB

## 66. Understand traffic

The intended path is:

```text
Browser
   |
Route53
   |
ALB
   |
Kubernetes worker
   |
NodePort
   |
Service
   |
Pod :8080
```

---

## 67. Verify ALB

In AWS, open:

```text
EC2
 -> Load Balancers
```

Check:

```text
Load balancer exists
Listener exists
Target group exists
Targets registered
Targets healthy
Security group permits traffic
Target port is correct
```

---

## 68. Test ALB directly

Get the ALB DNS name from:

```bash
terraform output
```

Test:

```bash
curl http://ALB_DNS_NAME
```

If it fails, check ALB target health before changing application code.

---

# PART 25 — ROUTE53 AND GODADDY

## 69. Understand the DNS relationship

If the domain is registered with GoDaddy, the domain can still use Route53 DNS.

The important distinction is:

```text
GoDaddy = domain registrar
Route53 = DNS hosting
```

---

## 70. Get Route53 name servers

If Terraform creates a Route53 hosted zone:

```bash
terraform output
```

Or:

```bash
aws route53 list-hosted-zones-by-name
```

Get the hosted zone's name servers.

They look like:

```text
ns-123.awsdns-45.com
ns-678.awsdns-90.net
ns-111.awsdns-22.org
ns-222.awsdns-33.co.uk
```

Use the exact values AWS provides.

---

## 71. Configure GoDaddy

In GoDaddy:

```text
Domain
 -> DNS / Nameservers
 -> Change Nameservers
```

Replace the registrar nameservers with the Route53 nameservers.

Do not enter:

```text
http://...
```

Do not enter:

```text
https://...
```

Do not enter the domain name as a nameserver.

Enter only the nameserver hostnames supplied by Route53.

---

## 72. Create DNS record

In Route53, create the record required by the project.

Example:

```text
devshop.example.com
```

Point it to the ALB using the appropriate Route53 alias record.

DNS propagation can take time.

Test:

```bash
dig devshop.example.com
```

---

# PART 26 — S3

## 73. Verify S3

List buckets:

```bash
aws s3 ls
```

Find the project bucket.

Do not make the bucket public unless the project explicitly requires it.

---

# PART 27 — IAM

## 74. Verify permissions

Review:

```text
EC2 IAM roles
Jenkins permissions
Terraform permissions
S3 permissions
RDS-related permissions
```

Prefer IAM roles over long-lived access keys wherever practical.

Use least privilege.

---

# PART 28 — JENKINS TO NEXUS CREDENTIALS

## 75. Create Nexus credentials in Jenkins

Open:

```text
Manage Jenkins
 -> Credentials
 -> System
 -> Global credentials
 -> Add Credentials
```

Create the credential type required by the Jenkinsfile.

Typical values:

```text
Username: Nexus username
Password: Nexus password
ID: nexus-credentials
```

The **ID must match the Jenkinsfile**.

Search:

```bash
grep -Rni "credentialsId" jenkins/
```

Use the exact ID expected by the pipeline.

---

# PART 29 — JENKINS KUBECONFIG

## 76. Obtain kubeconfig

On the Kubernetes control plane:

```bash
cat ~/.kube/config
```

Do not publish it.

Copy it securely to a temporary location accessible to the Jenkins administrator.

---

## 77. Create Jenkins Secret File

In Jenkins:

```text
Manage Jenkins
 -> Credentials
 -> System
 -> Global credentials
 -> Add Credentials
```

Choose:

```text
Kind: Secret file
```

Set an ID matching the Jenkinsfile, for example:

```text
kubeconfig
```

Upload the kubeconfig file.

---

## 78. Test Kubernetes access from Jenkins

The Jenkins execution environment must be able to run:

```bash
kubectl get nodes
```

The result should show Kubernetes nodes.

If it fails, check:

```text
kubeconfig
Kubernetes API address
network connectivity
port 6443
certificates
RBAC
```

---

# PART 30 — GITHUB

## 79. Check Git status

From the project root:

```bash
git status
```

---

## 80. Check `.gitignore`

Ensure these are ignored:

```text
*.pem
terraform.tfvars
secret.yaml
kubeconfig
.env
AWS credentials
```

Then:

```bash
git status
```

Make sure secrets are not staged.

---

## 81. Commit and push

```bash
git add .
git commit -m "Deploy DevShop DevOps project"
git push origin main
```

---

# PART 31 — GITHUB WEBHOOK

## 82. Configure Jenkins job

Create a Jenkins Pipeline job.

Configure it to use your GitHub repository.

The pipeline should use:

```text
jenkins/Jenkinsfile
```

---

## 83. Configure GitHub webhook

In GitHub:

```text
Repository
 -> Settings
 -> Webhooks
 -> Add webhook
```

Set the Jenkins webhook URL required by your Jenkins installation.

The normal flow is:

```text
git push
   |
GitHub
   |
Webhook
   |
Jenkins
```

---

# PART 32 — REVIEW THE JENKINSFILE BEFORE RUNNING

## 84. Open the Jenkinsfile

From the repository:

```bash
cat jenkins/Jenkinsfile
```

or:

```bash
nano jenkins/Jenkinsfile
```

Verify the stages.

Expected logical stages:

```text
Checkout
Build
Test
Maven Publish
Docker Build
Docker Push
Kubernetes Deploy
Rollout Verify
```

---

## 85. Confirm there is no Ansible-worker deployment

Search:

```bash
grep -Rni "ansible" jenkins/Jenkinsfile
```

The Jenkinsfile must not depend on:

```text
agent { label 'ansible' }
```

for Kubernetes deployment.

Jenkins itself should run:

```bash
kubectl
```

using its Kubernetes credential.

---

# PART 33 — JENKINS PIPELINE: CHECKOUT

## 86. Run the pipeline

Click:

```text
Build Now
```

or trigger it through GitHub.

The first stage checks out the repository.

If checkout fails, check:

```text
Repository URL
Git credentials
Branch
Network
Webhook
```

---

# PART 34 — JENKINS PIPELINE: MAVEN

## 87. Build and test

The pipeline should execute the equivalent of:

```bash
mvn clean test package
```

If this stage fails:

```text
STOP
```

Do not continue to Docker/Kubernetes troubleshooting.

Run the same command manually on the Jenkins server:

```bash
cd workspace/YOUR_JOB
mvn clean test package
```

---

# PART 35 — JENKINS PIPELINE: MAVEN/NEXUS

## 88. Publish the artifact

The generated JAR is published to Nexus Maven.

Conceptual flow:

```text
devshop.jar
     |
     v
Nexus Maven Repository
```

Verify in Nexus that the artifact exists.

If publishing fails, check:

```text
Nexus URL
Repository name
Username/password
Jenkins credential ID
Maven configuration
Network
```

---

# PART 36 — JENKINS PIPELINE: DOCKER BUILD

## 89. Build image

The pipeline should build an image using a unique tag.

Example:

```text
devshop:25
```

or:

```text
NEXUS_HOST:PORT/devshop:25
```

Do not rely on `latest` for deployment if the project is designed for immutable build tags.

Test manually:

```bash
docker build -t devshop:test application/
```

---

# PART 37 — JENKINS PIPELINE: DOCKER PUSH

## 90. Login

Example:

```bash
docker login NEXUS_HOST:PORT
```

Enter Nexus credentials.

---

## 91. Push

Example:

```bash
docker push NEXUS_HOST:PORT/devshop:BUILD_NUMBER
```

Verify the image appears in Nexus.

If push fails:

```text
Check registry address
Check Docker repository
Check credentials
Check Docker permissions
Check security group
Check Nexus availability
```

---

# PART 38 — JENKINS PIPELINE: KUBERNETES DEPLOYMENT

## 92. Test kubeconfig first

On Jenkins:

```bash
kubectl get nodes
```

If that fails, fix it before running deployment.

---

## 93. Apply Kubernetes manifests

The pipeline can run the project's equivalent of:

```bash
kubectl apply -f kubernetes/
```

The deployment must use the newly built image.

Example:

```text
NEXUS_HOST:PORT/devshop:25
```

---

## 94. Check deployment

```bash
kubectl -n devshop get deployment
```

Then:

```bash
kubectl -n devshop get pods
```

---

# PART 39 — ROLLOUT VERIFICATION

## 95. Wait for rollout

Example:

```bash
kubectl -n devshop rollout status deployment/devshop
```

Success means the Deployment has completed its rollout.

Then:

```bash
kubectl -n devshop get pods -o wide
```

Pods should be:

```text
Running
```

and ready.

---

# PART 40 — TROUBLESHOOT PODS

## 96. CrashLoopBackOff

Run:

```bash
kubectl -n devshop get pods
```

Get the Pod name:

```bash
kubectl -n devshop logs POD_NAME
```

Then:

```bash
kubectl -n devshop describe pod POD_NAME
```

Check:

```text
RDS URL
Username
Password
Secret
ConfigMap
Image
Container port
Java startup
Probes
```

---

## 97. ImagePullBackOff

Run:

```bash
kubectl -n devshop describe pod POD_NAME
```

Look at Events.

Check:

```text
Image name
Image tag
Nexus address
Registry authentication
Nexus network access
Image existence
```

If a private registry requires authentication, Kubernetes may need an image pull secret according to the project's configuration.

---

## 98. Pending Pod

Run:

```bash
kubectl -n devshop describe pod POD_NAME
```

Common causes:

```text
No suitable node
Node selector mismatch
Taints
Insufficient CPU/memory
PVC problem
```

Check:

```bash
kubectl get nodes --show-labels
```

---

# PART 41 — TEST APPLICATION TO RDS

## 99. Confirm application environment

Inspect:

```bash
kubectl -n devshop describe deployment devshop
```

Check the environment variables and Secret/ConfigMap references.

Do not print actual passwords.

---

## 100. Check logs

```bash
kubectl -n devshop logs deployment/devshop
```

Look for:

```text
Started ...
HikariPool
MySQL connection
```

If you see connection timeouts, return to RDS security groups and network routing.

---

# PART 42 — TEST SERVICE AND ALB

## 101. Check Service

```bash
kubectl -n devshop get svc
```

Then:

```bash
kubectl -n devshop get endpoints
```

There should be Pod endpoints.

---

## 102. Check ALB target health

In AWS:

```text
EC2
 -> Load Balancers
 -> Target Groups
 -> Targets
```

Targets should be healthy.

If unhealthy, compare:

```text
ALB target port
NodePort
Service targetPort
Container port
Health-check path
Security groups
```

---

# PART 43 — FINAL URL TEST

## 103. Test ALB

```bash
curl -i http://ALB_DNS_NAME
```

---

## 104. Test Route53

```bash
dig devshop.example.com
```

Then:

```bash
curl -i http://devshop.example.com
```

If HTTPS is configured, use the project's HTTPS endpoint.

---

# PART 44 — COMPLETE CI/CD TEST

## 105. Make a small application change

Change a harmless value or application code.

Then:

```bash
git status
git add .
git commit -m "Test DevShop CI/CD"
git push origin main
```

Expected:

```text
GitHub
  |
Webhook
  |
Jenkins
  |
Checkout
  |
Maven
  |
Tests
  |
JAR -> Nexus
  |
Docker Build
  |
Docker Push -> Nexus
  |
kubectl
  |
Kubernetes
  |
New Pod
  |
ALB
  |
User
```

---

## 106. Verify the new version

In Jenkins, identify the build number.

Then:

```bash
kubectl -n devshop get deployment devshop -o yaml
```

Find the image.

Then:

```bash
kubectl -n devshop rollout history deployment/devshop
```

---

# PART 45 — TROUBLESHOOTING REFERENCE

## Terraform

Run:

```bash
terraform validate
terraform plan
```

Check:

```text
AWS credentials
IAM
Region
AZs
CIDRs
Key pair
Resource limits
```

---

## AWS EC2

Check:

```text
Instance state
Public/private IP
Security groups
Subnet
Route table
Key pair
```

---

## SSH

Test:

```bash
ssh -i ~/.ssh/devshop.pem ubuntu@HOST
```

---

## Ansible

Test:

```bash
ansible all -m ping
```

Detailed:

```bash
ansible HOST -m ping -vvv
```

---

## Kubernetes

Check:

```bash
kubectl get nodes
kubectl get pods -A
kubectl -n devshop get all
```

---

## Wrong Kubernetes node name

If:

```text
nodes "JENKINS_NODE" not found
```

run:

```bash
kubectl get nodes
```

Use the real name.

---

## Missing namespace

If:

```text
namespaces "devshop" not found
```

run:

```bash
kubectl create namespace devshop
```

or apply the project's namespace manifest.

---

## Jenkins cannot run kubectl

Check:

```bash
kubectl version --client
kubectl get nodes
```

Then verify:

```text
Kubeconfig
API endpoint
Port 6443
Security groups
Certificates
RBAC
```

---

## Jenkins cannot install packages

If apt reports:

```text
No package matching ...
```

check:

```bash
sudo apt update
apt-cache policy PACKAGE_NAME
```

For Kubernetes packages, verify the Kubernetes apt repository.

For Jenkins, verify the Jenkins key and repository.

---

## AWS CLI unavailable through apt

If:

```text
No package matching 'awscli' is available
```

do not assume the package name is the only problem.

Check:

```bash
sudo apt update
apt-cache policy awscli
```

Also verify the Ubuntu release and configured repositories.

If the project requires AWS CLI v2, use the installation method specified by the project's provisioning role rather than mixing package versions.

---

## RDS timeout

For:

```text
ERROR 2003
Can't connect to MySQL server
```

check:

```text
RDS available
Correct endpoint
3306
Security groups
VPC
Subnets
Routes
NACL
DNS
Source network
```

---

# PART 46 — SECURITY RULES

Never commit:

```text
*.pem
terraform.tfvars
secret.yaml with real credentials
kubeconfig
AWS credentials
Nexus passwords
GitHub tokens
.env files containing secrets
```

Check before pushing:

```bash
git status
git diff --cached
```

If a secret was accidentally committed, removing the file in a later commit is not enough; rotate the exposed credential and clean repository history as appropriate.

---

# PART 47 — WHAT EACH TOOL DOES

## Terraform

Creates infrastructure:

```text
VPC
EC2
RDS
S3
ALB
Security Groups
IAM
Route53
```

Command:

```bash
terraform plan
terraform apply
```

---

## Ansible

Configures EC2 servers:

```text
Java
Maven
Docker
Jenkins
Nexus
Kubernetes
AWS CLI
```

Command:

```bash
ansible-playbook site.yml
```

There is no Ansible worker.

---

## Jenkins

Performs:

```text
Checkout
Build
Test
Package
Publish
Docker build
Docker push
Kubernetes deployment
```

---

## Maven

Builds and tests the Java application:

```bash
mvn clean test package
```

---

## Nexus

Stores:

```text
Maven artifacts
Docker images
```

---

## Docker

Packages the application into a container image.

---

## Kubernetes

Runs the application:

```text
Pods
Deployment
Service
Rolling updates
Self-healing
Scheduling
```

---

## ALB

Receives external HTTP/HTTPS traffic and forwards it toward the application.

---

## Route53

Provides DNS resolution.

---

## RDS

Provides MySQL database service.

---

## S3

Provides object storage.

---

# PART 48 — EXACT IMPLEMENTATION ORDER

Follow this order:

```text
1. Prepare AWS
2. Create EC2 key pair
3. Configure AWS CLI
4. Extract project
5. Verify Java application
6. Run Maven tests
7. Configure Terraform variables
8. terraform init
9. terraform fmt
10. terraform validate
11. terraform plan
12. Confirm NO ansible-worker
13. terraform apply
14. Capture Terraform outputs
15. Test SSH
16. Configure Ansible inventory
17. Confirm NO ansible-worker in inventory
18. ansible all -m ping
19. Run Ansible
20. Verify Java
21. Verify Maven
22. Verify Docker
23. Install/verify Jenkins
24. Configure Nexus
25. Install/verify Kubernetes
26. Initialize control plane
27. Install CNI
28. Join workers
29. Verify nodes
30. Label nodes
31. Verify RDS
32. Test RDS network
33. Create Kubernetes namespace
34. Create Secret
35. Create ConfigMap
36. Apply Deployment
37. Apply Service
38. Verify Pods
39. Verify Service endpoints
40. Verify ALB
41. Configure Route53
42. Configure GoDaddy nameservers if Route53 is authoritative
43. Verify S3
44. Verify IAM
45. Configure Jenkins Nexus credentials
46. Configure Jenkins kubeconfig credential
47. Configure GitHub repository
48. Configure GitHub webhook
49. Create Jenkins Pipeline
50. Checkout
51. Maven build
52. Maven test
53. Maven publish
54. Docker build
55. Docker push
56. kubectl deployment
57. Rollout verification
58. ALB health verification
59. Route53 verification
60. Application health test
61. RDS/application test
62. Perform a second Git push
63. Verify the complete CI/CD cycle
```

---

# PART 49 — FINAL VERIFICATION CHECKLIST

```text
[ ] AWS credentials work
[ ] Terraform initializes
[ ] Terraform validates
[ ] Terraform plan succeeds
[ ] No ansible-worker exists
[ ] AWS infrastructure exists
[ ] SSH works
[ ] Ansible inventory works
[ ] No ansible-worker exists in inventory
[ ] ansible all -m ping works
[ ] Java 21 works
[ ] Maven works
[ ] Docker works
[ ] Jenkins works
[ ] Nexus works
[ ] Kubernetes packages installed
[ ] Kubernetes control plane works
[ ] CNI works
[ ] Workers are Ready
[ ] No ansible-worker Kubernetes node
[ ] Nodes have correct labels
[ ] RDS is available
[ ] RDS port 3306 is reachable from the application network
[ ] devshop namespace exists
[ ] Kubernetes Secret exists
[ ] ConfigMap exists
[ ] Deployment exists
[ ] Pods are Running
[ ] Service exists
[ ] Service has endpoints
[ ] ALB exists
[ ] ALB targets are healthy
[ ] Route53 record resolves
[ ] GoDaddy nameservers point to Route53 when applicable
[ ] S3 exists
[ ] IAM permissions work
[ ] Jenkins Nexus credentials work
[ ] Jenkins kubeconfig works
[ ] GitHub webhook works
[ ] Jenkins checkout works
[ ] Maven build passes
[ ] Maven tests pass
[ ] Maven artifact reaches Nexus
[ ] Docker image builds
[ ] Docker image reaches Nexus
[ ] kubectl works from Jenkins
[ ] Kubernetes rollout succeeds
[ ] Application logs are healthy
[ ] Application connects to RDS
[ ] ALB responds
[ ] Domain responds
[ ] A second Git push triggers a successful deployment
```

---

# PART 50 — THE FINAL WORKING FLOW

Once everything is implemented, a normal application change should require only:

```text
Developer changes code
        |
        v
git add .
git commit
git push
        |
        v
GitHub
        |
        v
Webhook
        |
        v
Jenkins
        |
        +---- mvn clean test package
        |
        +---- publish JAR to Nexus
        |
        +---- docker build
        |
        +---- docker push
        |
        +---- kubectl apply/deploy
        |
        v
Kubernetes
        |
        v
DevShop Pod
        |
        v
Service
        |
        v
ALB
        |
        v
Route53
        |
        v
User
```

Terraform is used when AWS infrastructure changes.

Ansible is used when EC2 server configuration changes.

Jenkins is used for application CI/CD.

There is **no Ansible worker**.

The final division of responsibility is:

```text
Terraform   = CREATE infrastructure
Ansible     = CONFIGURE servers
Jenkins     = BUILD + TEST + PACKAGE + DEPLOY
Maven       = BUILD Java application
Nexus       = STORE artifacts/images
Docker      = CONTAINERIZE application
Kubernetes  = RUN application
ALB         = LOAD BALANCE
Route53     = DNS
RDS         = MYSQL DATABASE
S3          = OBJECT STORAGE
IAM         = PERMISSIONS
```
