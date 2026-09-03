# DevShop DevOps Project — Complete Step-by-Step Build Guide

## Revised implementation: NO Ansible Worker

This guide explains how to build the revised `devshop-devops-project-no-ansible-worker.zip` from scratch.

**Architecture rule:** there is no Ansible worker. The dedicated Ansible server configures the target EC2 machines over SSH. Jenkins handles CI/CD and deploys directly to Kubernetes with `kubectl`, using a Jenkins kubeconfig credential.

---

## 1. Final architecture

```text
                         GitHub
                           |
                        webhook
                           |
                           v
                    +---------------+
                    |    Jenkins    |
                    | Java / Maven  |
                    | Docker/kubectl|
                    +-------+-------+
                            |
             +--------------+---------------+
             |                              |
             v                              v
      +-------------+               +---------------+
      |    Nexus    |               |  Kubernetes   |
      | Maven/Docker|               | Control Plane |
      +-------------+               +-------+-------+
                                            |
                                  +---------+---------+
                                  |                   |
                                  v                   v
                             Web Worker           Web Worker
                             DevShop Pod          DevShop Pod
                                  |                   |
                                  +---------+---------+
                                            |
                                            v
                                       AWS ALB
                                            |
                                         Route53
                                            |
                                          User

             Ansible Server
                    |
             configures EC2s

             Terraform
                    |
             creates AWS resources
```

---

## 2. Component responsibilities

| Component | Responsibility |
|---|---|
| AWS | Cloud infrastructure |
| VPC | Network isolation |
| Public subnet | Internet-facing resources |
| Private subnet | Internal resources |
| Internet Gateway | Public internet access |
| NAT Gateway | Outbound private-subnet access |
| Security Groups | Network firewall |
| IAM | AWS permissions |
| Terraform | Infrastructure provisioning |
| Ansible | EC2/server configuration |
| Jenkins | CI/CD orchestration |
| Maven | Java build, test and package |
| Nexus | Maven/Docker artifact repository |
| Docker | Application containerization |
| Kubernetes | Application orchestration |
| kubectl | Kubernetes administration/deployment |
| RDS | MySQL database |
| S3 | Object storage |
| ALB | HTTP load balancing |
| Route53 | DNS |
| GitHub | Source control |

---

## 3. EC2 roles

The revised design has these logical roles:

```text
terraform-server
ansible-server
k8s-control-plane
jenkins-worker
maven-worker
nexus-worker
web-worker
```

There is deliberately **no `ansible-worker`**.

The Ansible server is the Ansible control node. Ansible is agentless and connects to managed nodes over SSH.

---

# PART A — PREPARE THE ENVIRONMENT

## 4. Prerequisites

Prepare:

1. AWS account.
2. IAM identity with permissions required by this project.
3. EC2 key pair.
4. GitHub repository.
5. Linux/Ubuntu machine for Terraform/Ansible.
6. Your public IP address.
7. The project ZIP.

Recommended AWS region:

```text
ap-south-1
```

---

## 5. Extract the project

```bash
unzip devshop-devops-project-no-ansible-worker.zip
cd devshop-devops
```

Inspect:

```bash
find . -maxdepth 2 -type f | sort
```

Main directories:

```text
application/
terraform/
ansible/
kubernetes/
jenkins/
scripts/
docs/
```

---

# PART B — VERIFY THE JAVA APPLICATION FIRST

## 6. Enter the application

```bash
cd application
```

Important files:

```text
pom.xml
Dockerfile
src/
```

The application is a Spring Boot Java application and normally listens on port `8080`.

---

## 7. Verify Java

```bash
java -version
```

The project targets Java 21.

Expected major version:

```text
21
```

---

## 8. Verify Maven

```bash
mvn -version
```

Confirm Maven is using Java 21.

---

## 9. Build and test locally

```bash
mvn clean test package
```

Check:

```bash
ls -lh target/
```

You should get the built JAR.

Run:

```bash
java -jar target/devshop-1.0.0.jar
```

The application should listen on:

```text
http://localhost:8080
```

If the command is running on a remote EC2 server, `localhost` refers to that EC2 server, not your Windows computer.

Stop the test application with:

```text
Ctrl+C
```

Do not continue to infrastructure troubleshooting until the application can build successfully.

---

# PART C — AWS CREDENTIALS

## 10. Configure AWS credentials

For a development machine, configure AWS CLI:

```bash
aws configure
```

Enter:

```text
AWS Access Key ID
AWS Secret Access Key
Default region: ap-south-1
Output: json
```

Verify:

```bash
aws sts get-caller-identity
```

Never put access keys directly into Terraform `.tf` files.

Never commit credentials to Git.

For EC2-based automation, IAM roles are preferable when practical.

---

# PART D — TERRAFORM

## 11. Enter Terraform

```bash
cd ../terraform
```

Copy:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit:

```bash
nano terraform.tfvars
```

Set values such as:

```hcl
aws_region = "ap-south-1"

project_name = "devshop"

environment = "dev"

key_name = "YOUR_EC2_KEY_PAIR"

admin_cidr = "YOUR_PUBLIC_IP/32"

worker_count = 4

rds_username = "devshop"

rds_password = "USE_A_STRONG_PASSWORD"

rds_db_name = "devshop"
```

Use the exact variable names defined by this project's `variables.tf`.

Do not commit `terraform.tfvars`.

---

## 12. Understand Terraform before running it

Terraform describes the desired AWS state.

Conceptually:

```text
Terraform
   |
   +--> VPC
   +--> Subnets
   +--> Routes
   +--> Internet/NAT Gateway
   +--> Security Groups
   +--> IAM
   +--> EC2
   +--> RDS
   +--> S3
   +--> ALB
   +--> Route53
```

Terraform is infrastructure-as-code. It is not the tool that builds the Java application.

---

## 13. Initialize Terraform

```bash
terraform init
```

This downloads providers and initializes the working directory.

---

## 14. Format Terraform

```bash
terraform fmt -recursive
```

---

## 15. Validate Terraform

```bash
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

---

## 16. Review the plan

```bash
terraform plan
```

Look for:

```text
VPC
subnets
route tables
internet gateway
NAT gateway
security groups
IAM
EC2
RDS
S3
ALB
Route53
```

Very important:

```text
There must be NO ansible-worker.
```

The worker count is reduced accordingly.

---

## 17. Create infrastructure

```bash
terraform apply
```

Review the plan and enter:

```text
yes
```

Wait for completion.

---

## 18. Capture outputs

```bash
terraform output
```

Record the values for:

```text
Terraform server
Ansible server
Kubernetes control plane
worker IPs
Nexus
RDS
ALB
S3
Route53
```

These values are needed for configuration.

---

# PART E — SSH

## 19. Protect your EC2 key

```bash
chmod 400 ~/.ssh/devshop.pem
```

Use the actual filename of your key.

---

## 20. Test Ansible server SSH

```bash
ssh -i ~/.ssh/devshop.pem ubuntu@ANSIBLE_SERVER_IP
```

If SSH fails, check:

- instance state
- public IP
- security group
- key pair
- username
- your current public IP
- routing

Do not move to Ansible until SSH works.

---

# PART F — ANSIBLE

## 21. Configure inventory

From the project:

```bash
cd ansible
```

Copy:

```bash
cp inventory/hosts.ini.example inventory/hosts.ini
```

Edit:

```bash
nano inventory/hosts.ini
```

The inventory should have logical groups for:

```text
terraform
ansible
kube_control_plane
kube_workers
```

Example worker entries:

```ini
[kube_workers]
JENKINS_WORKER_IP ansible_host=JENKINS_WORKER_IP node_role=jenkins
MAVEN_WORKER_IP ansible_host=MAVEN_WORKER_IP node_role=maven
NEXUS_WORKER_IP ansible_host=NEXUS_WORKER_IP node_role=nexus
WEB_WORKER_IP ansible_host=WEB_WORKER_IP node_role=web
```

Do not create an Ansible worker group.

---

## 22. Configure ansible.cfg

Check:

```bash
nano ansible.cfg
```

Make sure the private key is correct.

Example:

```ini
private_key_file = ~/.ssh/devshop.pem
```

---

## 23. Test Ansible

```bash
ansible all -m ping
```

Successful hosts return:

```text
pong
```

If one fails, fix it before running the full playbook.

---

## 24. Run server configuration

Run the main configuration playbook supplied by the project, for example:

```bash
ansible-playbook site.yml
```

The roles configure the required servers.

Typical software includes:

```text
Docker
Java
Maven
Jenkins
Nexus
Kubernetes packages
kubectl
AWS CLI
```

---

# PART G — DOCKER

## 25. Verify Docker on required machines

```bash
docker --version
```

Test:

```bash
docker run hello-world
```

The Jenkins machine must be able to execute Docker commands because Jenkins builds and pushes the application image.

---

# PART H — JAVA AND MAVEN

## 26. Verify Java 21

On the Jenkins/build machine:

```bash
java -version
```

Then:

```bash
mvn -version
```

Then:

```bash
mvn clean test
```

---

# PART I — NEXUS

## 27. Configure Nexus

Nexus provides:

```text
Maven repository
Docker repository
```

The flow is:

```text
Jenkins
  |
  +--> devshop.jar --> Nexus Maven
  |
  +--> Docker image --> Nexus Docker
```

Configure the repositories required by the project.

The Docker registry is expected to be reachable through the configured Nexus Docker port, commonly:

```text
8082
```

Use the project's actual configuration rather than blindly assuming a port.

---

## 28. Test Nexus connectivity

From Jenkins:

```bash
curl http://NEXUS_HOST:8081
```

For the Docker registry, use the configured Docker registry endpoint.

Make sure security groups allow the Jenkins server to reach Nexus.

---

# PART J — KUBERNETES

## 29. Configure Kubernetes packages

The Kubernetes machines need:

```text
kubeadm
kubelet
kubectl
container runtime
CNI
```

Use the project's Kubernetes Ansible playbook.

---

## 30. Initialize the control plane

Run the project's Kubernetes playbook, for example:

```bash
ansible-playbook kubernetes.yml
```

The process is:

```text
install Kubernetes
       |
configure runtime
       |
initialize control plane
       |
install CNI
       |
generate join command
       |
join workers
```

---

## 31. Verify Kubernetes control plane

On the control plane:

```bash
kubectl get nodes
```

Then:

```bash
kubectl get pods -A
```

The system pods must be healthy.

---

## 32. Verify all workers

```bash
kubectl get nodes -o wide
```

Expected roles include:

```text
control plane
jenkins
maven
nexus
web
```

There must be no:

```text
ansible-worker
```

---

## 33. Label nodes carefully

First:

```bash
kubectl get nodes
```

Use the actual Kubernetes node names.

Never type a placeholder such as:

```bash
kubectl label node JENKINS_NODE node-role=jenkins
```

unless the actual node name is literally `JENKINS_NODE`.

Use:

```bash
kubectl label node <REAL_NODE_NAME> node-role=jenkins
```

and apply the other labels expected by the manifests.

---

# PART K — RDS

## 34. Get RDS endpoint

From Terraform:

```bash
terraform output
```

Find the RDS endpoint.

It will resemble:

```text
xxxxx.rds.amazonaws.com
```

---

## 35. Understand the database connection

The Spring Boot URL normally has the structure:

```text
jdbc:mysql://RDS_ENDPOINT:3306/DATABASE_NAME
```

Do not use only the hostname where a JDBC URL is required.

The username and password should come from environment variables/Kubernetes Secrets.

---

## 36. Check RDS security group

MySQL requires:

```text
TCP 3306
```

The RDS security group should allow the application workload/network to connect.

Do not expose RDS publicly without a deliberate security design.

---

## 37. Test RDS connectivity

From an allowed host:

```bash
mysql -h RDS_ENDPOINT -P 3306 -u USERNAME -p
```

If this times out, investigate:

```text
RDS state
VPC
subnets
route tables
security groups
network ACLs
port 3306
```

Do not assume a timeout is a password problem.

---

# PART L — KUBERNETES APPLICATION CONFIGURATION

## 38. Create the namespace

Check:

```bash
kubectl get namespaces
```

If the project uses `devshop`:

```bash
kubectl create namespace devshop
```

Then:

```bash
kubectl get namespace devshop
```

This prevents:

```text
namespaces "devshop" not found
```

---

## 39. Create the Kubernetes Secret

Inside the Kubernetes directory:

```bash
cp secret.yaml.example secret.yaml
```

Edit:

```bash
nano secret.yaml
```

Add the RDS credentials and other secret values required by the application.

Apply:

```bash
kubectl apply -f secret.yaml
```

Verify only the secret metadata:

```bash
kubectl -n devshop get secrets
```

Do not commit `secret.yaml`.

---

## 40. Configure ConfigMap

Use ConfigMap for non-secret values such as:

```text
RDS hostname
port
database name
application configuration
```

Passwords belong in Secrets.

---

## 41. Apply namespace/application manifests

Apply the manifests in the order required by the project.

A typical order is:

```text
namespace
secret
configmap
deployment
service
```

Check:

```bash
kubectl -n devshop get all
```

---

# PART M — ALB

## 42. Understand the traffic path

The external traffic path is:

```text
Browser
   |
   v
Route53
   |
   v
AWS ALB
   |
   v
Kubernetes worker
   |
   v
NodePort
   |
   v
Service
   |
   v
DevShop Pod :8080
```

---

## 43. Verify ALB

Check:

```text
ALB exists
listener exists
target group exists
targets are healthy
security group allows HTTP/HTTPS
target port matches the Kubernetes exposure
```

The health-check endpoint must actually exist in the application.

---

# PART N — ROUTE53

## 44. Configure DNS

If you own a domain:

```text
devshop.example.com
```

create the appropriate Route53 record pointing to the ALB.

If you do not have a domain, use the ALB DNS name for initial testing.

---

# PART O — S3 AND IAM

## 45. Verify S3

Terraform creates the project bucket.

Use it for the storage purpose defined by the project.

Do not make the bucket public unless explicitly required.

---

## 46. Verify IAM

IAM should provide only the permissions required by each component.

Prefer:

```text
IAM role
```

over hard-coded access keys where possible.

---

# PART P — JENKINS

## 47. Open Jenkins

Open Jenkins using the Jenkins server address.

Complete:

```text
initial unlock
plugins
admin user
Jenkins URL
```

---

## 48. Verify Jenkins tools

On the Jenkins machine:

```bash
java -version
mvn -version
docker --version
kubectl version --client
git --version
```

All must work.

This is especially important in the revised design because Jenkins itself performs Kubernetes deployment.

---

# PART Q — JENKINS CREDENTIALS

## 49. Nexus credentials

Create Jenkins credentials for Nexus.

They are used to:

```text
publish Maven artifacts
login to Docker registry
```

Use the credential IDs expected by the project's Jenkinsfile.

---

## 50. Kubernetes kubeconfig credential

Obtain the Kubernetes kubeconfig from the control plane.

Do not put it in GitHub.

In Jenkins:

```text
Manage Jenkins
  -> Credentials
  -> Add Credentials
```

Create:

```text
Type: Secret file
ID: kubeconfig
```

Upload the kubeconfig.

The Jenkinsfile uses this credential to execute:

```bash
kubectl
```

against the Kubernetes cluster.

---

# PART R — GITHUB

## 51. Push project safely

Before committing:

```bash
git status
```

Check that sensitive files are excluded.

Never commit:

```text
*.pem
terraform.tfvars
secret.yaml
kubeconfig
AWS credentials
Nexus passwords
GitHub tokens
```

Then:

```bash
git add .
git commit -m "Deploy DevShop DevOps project"
git push origin main
```

---

## 52. Configure GitHub webhook

Configure GitHub to notify Jenkins when code changes.

The flow becomes:

```text
git push
   |
   v
GitHub
   |
 webhook
   |
   v
Jenkins
```

---

# PART S — JENKINS PIPELINE

## 53. Create Pipeline job

Create a Jenkins Pipeline job connected to the GitHub repository.

Use:

```text
jenkins/Jenkinsfile
```

The revised pipeline must not use:

```text
agent { label 'ansible' }
```

for deployment.

The deployment happens from Jenkins.

---

## 54. Pipeline stage: Checkout

Jenkins downloads the source code.

```text
GitHub
   |
   v
Jenkins workspace
```

---

## 55. Pipeline stage: Build/Test

Jenkins executes:

```bash
mvn clean test package
```

If this fails:

```text
STOP
```

Fix Maven/Java/application errors first.

---

## 56. Pipeline stage: Maven publish

Jenkins publishes the generated JAR to Nexus Maven.

Conceptually:

```text
devshop.jar
   |
   v
Nexus Maven Repository
```

---

## 57. Pipeline stage: Docker build

Jenkins builds:

```text
devshop:<BUILD_NUMBER>
```

Conceptually:

```bash
docker build -t NEXUS_HOST:8082/devshop:${BUILD_NUMBER} application/
```

Use the exact path and variables in the project's Jenkinsfile.

---

## 58. Pipeline stage: Docker push

Login:

```bash
docker login NEXUS_HOST:8082
```

Push:

```bash
docker push NEXUS_HOST:8082/devshop:${BUILD_NUMBER}
```

Now Nexus contains the image.

---

## 59. Pipeline stage: Kubernetes deployment

Jenkins loads the kubeconfig credential.

First test:

```bash
kubectl get nodes
```

Then:

```bash
kubectl apply -f kubernetes/
```

The Deployment should reference the newly built image tag.

For example:

```text
devshop:25
```

rather than always using:

```text
latest
```

---

## 60. Pipeline stage: rollout verification

Run:

```bash
kubectl -n devshop rollout status deployment/devshop
```

Then:

```bash
kubectl -n devshop get pods
```

The deployment is complete only when the rollout succeeds.

---

# PART T — FINAL APPLICATION TEST

## 61. Check Kubernetes

```bash
kubectl get nodes
kubectl get pods -A
```

Then:

```bash
kubectl -n devshop get all
```

---

## 62. Check application logs

If a pod is failing:

```bash
kubectl -n devshop logs <POD_NAME>
```

For startup problems, inspect:

```bash
kubectl -n devshop describe pod <POD_NAME>
```

---

## 63. Check the Service

```bash
kubectl -n devshop get svc
```

Confirm the configured port/NodePort.

---

## 64. Check ALB health

In AWS, verify:

```text
Load Balancer
  -> Target Group
  -> Targets
```

Targets should be healthy.

---

## 65. Test the final URL

Use:

```text
http://ALB_DNS_NAME
```

or the configured Route53 hostname.

Verify the application's health endpoint configured by the application.

---

# PART U — COMPLETE CI/CD FLOW

## 66. Normal developer workflow

After infrastructure is configured, the normal workflow is:

```text
Developer
   |
   | git push
   v
GitHub
   |
   | webhook
   v
Jenkins
   |
   +--> Checkout
   |
   +--> Maven Build
   |
   +--> Maven Test
   |
   +--> Maven Package
   |
   +--> Nexus Maven
   |
   +--> Docker Build
   |
   +--> Docker Push
   |
   +--> kubectl
   |
   v
Kubernetes
   |
   v
DevShop
```

You do not need to run Terraform for every Java code change.

You do not need to run Ansible for every Java code change.

---

# PART V — WHEN TO USE EACH TOOL

## 67. Terraform

Use Terraform when AWS infrastructure changes.

Example:

```text
new EC2
new subnet
new security group
RDS modification
ALB modification
S3 modification
IAM infrastructure
```

Commands:

```bash
terraform plan
terraform apply
```

---

## 68. Ansible

Use Ansible when EC2/server configuration changes.

Example:

```text
install Java
install Maven
install Docker
configure Jenkins
configure Nexus
configure Kubernetes
```

Command:

```bash
ansible-playbook site.yml
```

There is no Ansible worker.

---

## 69. Jenkins

Use Jenkins for:

```text
build
test
package
artifact publish
Docker build
Docker push
Kubernetes deployment
```

---

## 70. Kubernetes

Kubernetes is responsible for:

```text
pod scheduling
replicas
self-healing
rolling deployments
service discovery
application runtime
```

Jenkins tells Kubernetes what version to deploy; Kubernetes keeps that version running.

---

# PART W — TROUBLESHOOTING

## 71. Terraform failure

Check:

```bash
terraform validate
terraform plan
```

Then inspect:

```text
AWS credentials
IAM permissions
region
availability zones
CIDRs
key pair
resource limits
```

---

## 72. SSH failure

Check:

```text
EC2 running
correct IP
correct username
correct key
security group port 22
your public IP
```

---

## 73. Ansible failure

Run:

```bash
ansible all -m ping
```

Then test one host:

```bash
ansible <HOST_GROUP> -m ping
```

Fix connectivity first.

---

## 74. Kubernetes namespace error

If:

```text
namespaces "devshop" not found
```

run:

```bash
kubectl get namespaces
kubectl create namespace devshop
```

Then apply the resource again.

---

## 75. Kubernetes node-not-found error

If:

```text
nodes "JENKINS_NODE" not found
```

run:

```bash
kubectl get nodes
```

Use the actual node name.

---

## 76. Kubernetes apply annotation warning

If you see:

```text
missing kubectl.kubernetes.io/last-applied-configuration
```

the resource may have been created imperatively.

For example:

```bash
kubectl create namespace devshop
```

followed later by:

```bash
kubectl apply -f namespace.yaml
```

The annotation may be patched automatically.

Prefer a consistent declarative workflow for resources managed by Git.

---

## 77. RDS timeout

For:

```text
ERROR 2003 (HY000)
Can't connect to MySQL server
```

check:

```text
RDS state
endpoint
port 3306
security groups
VPC
subnets
routes
network ACLs
```

Test from a host that is actually allowed to reach RDS.

---

## 78. Spring Boot database configuration

A normal MySQL JDBC URL has this structure:

```properties
spring.datasource.url=jdbc:mysql://RDS_ENDPOINT:3306/DATABASE_NAME
```

Credentials should be injected through environment variables/Kubernetes Secrets.

Do not hard-code production passwords in `application.properties`.

---

## 79. Pod CrashLoopBackOff

Run:

```bash
kubectl -n devshop get pods
kubectl -n devshop logs <POD_NAME>
kubectl -n devshop describe pod <POD_NAME>
```

Check:

```text
database URL
database credentials
image
container port
environment variables
secret
configmap
readiness/liveness probes
```

---

## 80. ImagePullBackOff

Check:

```bash
kubectl -n devshop describe pod <POD_NAME>
```

Typical causes:

```text
wrong image name
wrong image tag
Nexus unreachable
Docker registry authentication
security group
image not pushed
```

Verify the image exists in Nexus.

---

## 81. Jenkins cannot run kubectl

Check:

```bash
kubectl version --client
kubectl get nodes
```

If `kubectl get nodes` fails on the Jenkins machine, verify:

```text
kubeconfig credential
Kubernetes API address
network connectivity
security groups
certificate
RBAC permissions
```

This is the most important difference from the old Ansible-worker design.

---

# PART X — SECURITY

## 82. Never commit secrets

Never commit:

```text
AWS credentials
PEM files
RDS passwords
Nexus passwords
GitHub tokens
kubeconfig
Kubernetes secret manifests containing real credentials
```

---

## 83. Use least privilege

Security should follow:

```text
only required permissions
only required network ports
only required users
only required AWS resources
```

---

## 84. Database security

Prefer:

```text
Private RDS
+
application security group
+
RDS security group
```

Do not expose MySQL publicly for convenience.

---

# PART Y — FINAL BUILD ORDER

## 85. Follow this exact order from zero

```text
01. Prepare AWS
02. Create EC2 key pair
03. Configure AWS credentials
04. Extract project
05. Test Java application
06. Configure Terraform
07. terraform init
08. terraform fmt
09. terraform validate
10. terraform plan
11. verify NO ansible-worker
12. terraform apply
13. capture Terraform outputs
14. test SSH
15. configure Ansible inventory
16. ansible ping
17. run server configuration
18. verify Docker
19. verify Java 21
20. verify Maven
21. configure Nexus
22. configure Kubernetes
23. initialize control plane
24. install CNI
25. join workers
26. verify nodes
27. label nodes
28. verify RDS
29. configure RDS connectivity
30. create devshop namespace
31. create Kubernetes Secret
32. create ConfigMap
33. configure Deployment
34. configure Service
35. configure ALB
36. configure Route53 if using a domain
37. configure S3/IAM
38. configure Jenkins
39. verify Java/Maven/Docker/kubectl
40. configure Nexus credentials
41. configure kubeconfig credential
42. configure GitHub
43. configure webhook
44. create Jenkins Pipeline
45. checkout
46. Maven build
47. Maven test
48. Maven publish
49. Docker build
50. Docker push
51. kubectl deployment
52. rollout verification
53. ALB health verification
54. DNS verification
55. application health test
56. RDS/application test
```

---

# 86. Final architecture rule

The revised project intentionally uses:

```text
Terraform
    |
    v
AWS Infrastructure
    |
    v
Ansible Server
    |
    v
Configure EC2 servers
    |
    v
Jenkins
    |
    +---- Maven
    |
    +---- Docker
    |
    +---- kubectl
    |
    v
Kubernetes
    |
    v
DevShop
```

There is **no Ansible worker**.

Ansible is agentless.

Jenkins is responsible for CI/CD and Kubernetes deployment.

---

# 87. Final verification checklist

```text
[ ] AWS credentials work
[ ] Terraform init works
[ ] Terraform validate works
[ ] Terraform plan works
[ ] No ansible-worker in Terraform plan
[ ] AWS infrastructure created
[ ] SSH works
[ ] Ansible inventory works
[ ] No ansible-worker in inventory
[ ] Ansible ping works
[ ] Docker works
[ ] Java 21 works
[ ] Maven works
[ ] Jenkins works
[ ] Nexus works
[ ] Kubernetes control plane works
[ ] Kubernetes CNI works
[ ] Kubernetes workers are Ready
[ ] No ansible-worker Kubernetes node
[ ] RDS is available
[ ] RDS network access works
[ ] devshop namespace exists
[ ] Kubernetes Secret exists
[ ] ConfigMap exists
[ ] Deployment exists
[ ] Service exists
[ ] ALB exists
[ ] ALB targets are healthy
[ ] Route53 works if configured
[ ] S3 exists
[ ] IAM is configured
[ ] Jenkins Nexus credentials work
[ ] Jenkins kubeconfig credential works
[ ] GitHub webhook works
[ ] Jenkins checkout works
[ ] Maven build passes
[ ] Maven tests pass
[ ] Maven artifact reaches Nexus
[ ] Docker image builds
[ ] Docker image reaches Nexus
[ ] kubectl works from Jenkins
[ ] Kubernetes rollout succeeds
[ ] Pods are Running
[ ] Application health endpoint works
[ ] Application reaches RDS
[ ] Final URL works
```

---

# 88. Project learning outcome

When this is complete, you can explain the project as a complete DevOps lifecycle:

```text
Code
 ↓
GitHub
 ↓
Jenkins
 ↓
Maven
 ↓
Nexus
 ↓
Docker
 ↓
Nexus Docker Registry
 ↓
Kubernetes
 ↓
ALB
 ↓
Route53
 ↓
User

Infrastructure:
Terraform → AWS

Configuration:
Ansible → EC2 servers

Data:
Application → RDS

Storage:
AWS → S3

Security:
IAM + Security Groups + Kubernetes Secrets
```

The key distinction is:

```text
Terraform = CREATE infrastructure

Ansible = CONFIGURE servers

Jenkins = BUILD + TEST + PACKAGE + DEPLOY

Nexus = STORE artifacts/images

Docker = CONTAINERIZE

Kubernetes = RUN application

ALB = LOAD BALANCE

Route53 = DNS

RDS = DATABASE

S3 = OBJECT STORAGE

IAM = PERMISSIONS
```

