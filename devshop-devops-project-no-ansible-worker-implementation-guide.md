**DevShop DevOps Project  
Complete Step-by-Step Implementation Guide  
**No Ansible Worker Architecture  
AWS • Terraform • Ansible • Kubernetes • Jenkins • Maven • Nexus • Docker • RDS • ALB • Route 53

_Based directly on devshop-devops-project-no-ansible-worker.zip  
04 September 2026_

This guide is written for someone implementing the project for the first time. Follow the phases in order and run the verification commands before moving to the next phase.

# 1\. Final Architecture

Developer pushes Java code to GitHub. GitHub triggers Jenkins. Jenkins checks out the project, runs Maven tests/package, publishes the Maven artifact to Nexus, builds a Docker image, pushes the image to Nexus Docker Registry, and deploys the image to the self-managed Kubernetes cluster. Kubernetes exposes the application through NodePort 30080. The AWS Application Load Balancer sends public HTTP traffic to that NodePort. Spring Boot connects privately to RDS MySQL.

GitHub  
|  
| webhook  
v  
Jenkins controller (jenkins-worker)  
|-- Maven build/test  
|-- Nexus Maven publish  
|-- Docker build  
|-- Nexus Docker push :8082  
|-- kubectl deployment  
v  
Kubernetes  
|-- control-plane  
|-- jenkins-worker  
|-- maven-worker  
|-- nexus-worker  
\`-- web-worker  
|  
\`-- DevShop Pod :8080  
|  
\`-- private RDS MySQL :3306  
<br/>Internet -> ALB :80 -> NodePort :30080 -> DevShop Pod :8080

# 2\. Which Server Do I Work On?

| Machine           | Purpose                 | Kubernetes    | What you do there                                     |
| ----------------- | ----------------------- | ------------- | ----------------------------------------------------- |
| Your PC           | Initial bootstrap/admin | No            | First Terraform apply, Git, SSH; keep project locally |
| terraform-server  | Terraform host          | No            | Run later Terraform plans/applies                     |
| ansible-server    | Ansible control node    | NO            | Install Ansible; run all playbooks                    |
| k8s-control-plane | Cluster control plane   | Control plane | kubeadm init; cluster administration                  |
| jenkins-worker    | Jenkins controller      | Worker        | Jenkins, Java, Maven, Docker, kubectl                 |
| maven-worker      | Dedicated Maven node    | Worker        | Java/Maven; future Jenkins agent                      |
| nexus-worker      | Artifact repository     | Worker        | Nexus container; Maven/Docker repositories            |
| web-worker        | Application node        | Worker        | Runs DevShop pods                                     |
| RDS               | Database                | No            | Private MySQL                                         |
| ALB               | Public load balancer    | No            | HTTP :80 to NodePort :30080                           |

**MOST IMPORTANT:** ansible-server is not a Kubernetes node. There is no ansible-worker EC2 instance.

**Bootstrap:** terraform-server cannot create itself. Run the first Terraform apply from your PC or an existing admin machine. Then you may use terraform-server for future Terraform work.

# 3\. Phase 0 — Prepare Your PC

- Install Git, Terraform (>=1.6), AWS CLI and OpenSSH.
- Select ap-south-1 unless you intentionally change aws_region.
- Create an EC2 key pair in AWS EC2 -> Key Pairs. Save the .pem securely.
- Find your public IP and set admin_cidr to YOUR_PUBLIC_IP/32. Do not use 0.0.0.0/0 for SSH.
- Clone/unzip the project. Work from the directory containing terraform/, ansible/, application/, kubernetes/ and jenkins/.

git clone &lt;YOUR-GITHUB-REPOSITORY&gt;  
cd devshop-devops  
aws configure  
aws sts get-caller-identity  
terraform -version  
git --version  
ssh -V

**AWS check:** aws sts get-caller-identity must return your AWS identity before Terraform is run.

# 4\. Phase 1 — Fix the Archive Before Deployment

The supplied archive is close to the intended design, but it is not safe to run unchanged. Make these corrections first.

## 4.1 Fix worker_count

terraform/ec2.tf defines exactly four worker names: jenkins-worker, maven-worker, nexus-worker and web-worker. Therefore worker_count must be 4. The example file currently says 5, which would make local.node_names\[count.index\] go out of range.

\# terraform/terraform.tfvars  
worker_count = 4

**Expected EC2 count:** 2 management servers + 1 control plane + 4 workers = 7 EC2 instances.

## 4.2 Fix Ansible site.yml conditional roles

The current file places 'when:' at play level for Jenkins/Nexus. Ansible does not allow when as a play attribute. Replace those two plays with task-level include_role blocks:

\- name: Configure Jenkins worker  
hosts: kube_workers  
become: true  
tasks:  
\- name: Install Jenkins role  
include_role:  
name: jenkins  
when: node_role == 'jenkins'  
<br/>\- name: Configure Nexus worker  
hosts: kube_workers  
become: true  
tasks:  
\- name: Install Nexus role  
include_role:  
name: nexus  
when: node_role == 'nexus'

**Alternative:** You can use separate inventory groups for Jenkins/Nexus, but the above is the smallest change to the supplied project.

## 4.3 Add the Kubernetes apt repository before installing kubelet/kubeadm/kubectl

The supplied kubernetes role tries to install kubelet/kubeadm/kubectl before adding the Kubernetes package repository. On a fresh Ubuntu host this causes 'No package matching kubelet is available'. Put repository setup before package installation:

\- name: Create Kubernetes keyring directory  
file:  
path: /etc/apt/keyrings  
state: directory  
mode: "0755"  
<br/>\- name: Download Kubernetes repository key  
shell: |  
curl -fsSL <https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key> |  
gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg  
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg  
args:  
creates: /etc/apt/keyrings/kubernetes-apt-keyring.gpg  
<br/>\- name: Add Kubernetes repository  
apt_repository:  
repo: "deb \[signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg\] <https://pkgs.k8s.io/core:/stable:/v1.33/deb/> /"  
state: present  
filename: kubernetes  
<br/>\- name: Update apt cache  
apt:  
update_cache: true  
<br/>\- name: Install Kubernetes packages  
apt:  
name:  
\- kubelet  
\- kubeadm  
\- kubectl  
state: present

**Version alignment:** The kubectl role in the archive uses the v1.33 repository. Keep kubeadm/kubelet/kubectl on the same minor release family for this project.

## 4.4 Jenkins controller labels

The Jenkinsfile uses labels maven, docker and jenkins. This project does not configure a separate Jenkins agent automatically. Therefore label the Jenkins controller with all three labels, or change the Jenkinsfile to use the controller for all stages.

Jenkins -> Manage Jenkins -> Nodes -> Built-In Node -> Configure  
Labels:  
jenkins maven docker

**Why:** Without matching labels, Jenkins can queue forever waiting for an agent.

# 5\. Phase 2 — Configure Terraform

WORK ON: Your PC for the first deployment. Later you may run Terraform from terraform-server.

cd terraform  
cp terraform.tfvars.example terraform.tfvars

Edit terraform.tfvars. Example structure:

aws_region = "ap-south-1"  
project_name = "devshop"  
environment = "dev"  
key_name = "YOUR_EXISTING_EC2_KEYPAIR"  
admin_cidr = "YOUR.PUBLIC.IP/32"  
domain_name = ""  
instance_type = "t3.medium"  
worker_instance_type = "t3.medium"  
worker_count = 4  
rds_username = "devshop"  
rds_password = "USE_A_STRONG_PASSWORD"  
rds_db_name = "devshop"

**Route 53:** Leave domain_name empty during the first successful deployment unless you already have a public Route 53 hosted zone for your domain. A GoDaddy domain by itself does not automatically create a Route 53 hosted zone.

## 5.1 Understand what Terraform creates

- VPC 10.0.0.0/16 with DNS enabled.
- Two public subnets in two availability zones.
- Two private subnets in two availability zones.
- Internet Gateway for public subnets.
- NAT Gateway for private subnet internet egress.
- Security groups for management, Kubernetes, ALB and RDS.
- 7 EC2 instances when worker_count=4.
- Private MySQL 8.0 RDS.
- Private/versioned S3 artifact bucket.
- Application Load Balancer and target group.
- Optional Route 53 app record.
- EC2 IAM role with S3 artifact permissions.

## 5.2 Terraform commands

cd terraform  
terraform init  
terraform fmt -recursive  
terraform validate  
terraform plan  
terraform apply

Review the plan carefully before typing yes. If Terraform reports an error, stop and fix it; do not continue with Ansible until the infrastructure is successfully created.

terraform output  
terraform output -json > outputs.json

**Do not commit:** terraform.tfvars, tfstate, .pem files, kubeconfig files, passwords or ansible/inventory/hosts.ini.

# 6\. Phase 3 — Verify AWS Infrastructure

WORK ON: Your PC, using AWS CLI/console. Do this before touching Ansible.

terraform output terraform_server_ip  
terraform output ansible_server_ip  
terraform output control_plane_ip  
terraform output worker_ips  
terraform output rds_endpoint  
terraform output alb_dns_name  
terraform output application_url

Create a small table for yourself with the values. You will need these IPs repeatedly.

| Value             | Example purpose                | Needed by            |
| ----------------- | ------------------------------ | -------------------- |
| ansible_server_ip | SSH target for Ansible control | You                  |
| control_plane_ip  | Kubernetes API/control plane   | Ansible/Jenkins      |
| jenkins-worker IP | Jenkins UI / controller        | You/GitHub           |
| maven-worker IP   | Maven worker                   | Ansible              |
| nexus-worker IP   | Nexus UI/registry              | Jenkins              |
| web-worker IP     | Kubernetes application node    | Ansible              |
| rds_endpoint      | MySQL endpoint                 | Kubernetes ConfigMap |
| alb_dns_name      | Public application endpoint    | Browser/DNS          |

## 6.1 Test SSH

chmod 400 ~/.ssh/YOUR_KEY.pem  
ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@&lt;ANSIBLE_SERVER_PUBLIC_IP&gt;  
ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@&lt;CONTROL_PLANE_PUBLIC_IP&gt;  
ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@&lt;JENKINS_PUBLIC_IP&gt;

**SSH failure:** Check that admin_cidr equals your current public IP/32 and that you are using the correct key pair.

# 7\. Phase 4 — Prepare ansible-server

WORK ON: ansible-server. This is the ONLY machine from which the supplied Ansible playbooks should be executed.

sudo apt update  
sudo apt install -y ansible git curl wget unzip jq ca-certificates gnupg  
ansible --version  
cd ~  
\# copy/clone the project here  
git clone &lt;YOUR-GITHUB-REPOSITORY&gt;  
cd devshop-devops  
ansible-galaxy collection install -r ansible/requirements.yml

## 7.1 Configure the inventory

cd ~/devshop-devops  
cp ansible/inventory/hosts.ini.example ansible/inventory/hosts.ini  
nano ansible/inventory/hosts.ini

Replace placeholders with the public IPs from Terraform. Use the four workers only; DO NOT add ansible-server to kube_workers.

\[terraform\]  
&lt;terraform-server-public-ip&gt;  
<br/>\[ansible\]  
&lt;ansible-server-public-ip&gt;  
<br/>\[kube_control_plane\]  
&lt;control-plane-public-ip&gt;  
<br/>\[kube_workers\]  
&lt;jenkins-public-ip&gt; ansible_host=&lt;jenkins-public-ip&gt; node_role=jenkins  
&lt;maven-public-ip&gt; ansible_host=&lt;maven-public-ip&gt; node_role=maven  
&lt;nexus-public-ip&gt; ansible_host=&lt;nexus-public-ip&gt; node_role=nexus  
&lt;web-public-ip&gt; ansible_host=&lt;web-public-ip&gt; node_role=web  
<br/>\[all:vars\]  
ansible_user=ubuntu

## 7.2 Configure ansible.cfg

nano ansible/ansible.cfg  
<br/>\[defaults\]  
inventory = inventory/hosts.ini  
host_key_checking = False  
interpreter_python = auto_silent  
remote_user = ubuntu  
private_key_file = /home/ubuntu/.ssh/YOUR_KEY.pem  
<br/>\[ssh_connection\]  
pipelining = True

**Private key:** Copy the EC2 private key securely to ansible-server or use an SSH agent. Never put the key into Git.

## 7.3 Test Ansible connectivity

cd ~/devshop-devops/ansible  
ansible all -m ping

Every host should return SUCCESS and a pong. If one host fails, fix SSH/network access before running playbooks.

# 8\. Phase 5 — Provision Common Software

WORK ON: ansible-server. TARGET: all EC2 nodes.

cd ~/devshop-devops/ansible  
ansible-playbook site.yml --syntax-check  
ansible-playbook site.yml

The common/docker part installs curl, wget, Git, unzip, jq, certificates, Docker/containerd and enables Docker. The Java role installs Java 21 on workers. The Jenkins role installs Jenkins, Maven, kubectl and Docker access on jenkins-worker. The Nexus role starts Nexus on nexus-worker.

## 8.1 Verify the roles

ansible all -a "docker --version"  
ansible kube_workers -a "java -version"  
ansible kube_workers -a "free -h"  
ansible kube_workers -a "systemctl is-active docker"  
ansible kube_control_plane -a "systemctl is-active containerd

## 8.2 Jenkins-specific verification

ansible kube_workers -a "systemctl is-active jenkins" --limit &lt;JENKINS_IP&gt;

**Jenkins repository issue:** If apt reports NO_PUBKEY for Jenkins, remove any old/broken Jenkins repository/key and re-run the current role's key/repository tasks. Do not bypass signature verification.

# 9\. Phase 6 — Build the Kubernetes Cluster

WORK ON: ansible-server. TARGET: k8s-control-plane + all four Kubernetes workers.

cd ~/devshop-devops/ansible  
ansible-playbook kubernetes.yml --syntax-check  
ansible-playbook kubernetes.yml

The playbook disables swap, installs Kubernetes packages, holds them, initializes the control plane with pod CIDR 10.244.0.0/16, installs Flannel, creates the ubuntu kubeconfig, generates a worker join command, and joins the four workers.

## 9.1 Verify the cluster

SSH to the control plane:

ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@&lt;CONTROL_PLANE_PUBLIC_IP&gt;  
kubectl get nodes -o wide  
kubectl get pods -A

All five Kubernetes machines should eventually be Ready: one control plane + four workers.

kubectl get nodes  
kubectl get pods -A  
kubectl get pods -n kube-flannel

**If a worker is NotReady:** Check kubelet status/logs, containerd configuration, swap status, and that VPC security group rules allow node-to-node traffic.

# 10\. Phase 7 — Install Metrics Server for HPA

WORK ON: control-plane. The archive contains an HPA but does not deploy metrics-server. Without resource metrics, HPA will usually show unknown/empty CPU metrics.

kubectl apply -f <https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml>  
kubectl -n kube-system edit deployment metrics-server

Add the kubelet TLS bypass argument if your learning cluster's kubelet certificates are not trusted by metrics-server:

args:  
\- --kubelet-insecure-tls  
\- --kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP

kubectl -n kube-system rollout status deployment/metrics-server  
kubectl top nodes

**Production:** Do not blindly use --kubelet-insecure-tls in a hardened production cluster. Configure proper kubelet certificate trust instead.

# 11\. Phase 8 — Configure Nexus

WORK ON: your browser + nexus-worker. Nexus is running in Docker on nexus-worker.

\# From your PC, open:  
http://&lt;NEXUS_PUBLIC_IP&gt;:8081

First login: retrieve the initial admin password from nexus-worker:

ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@&lt;NEXUS_PUBLIC_IP&gt;  
sudo docker exec nexus cat /nexus-data/admin.password

Complete the Nexus first-login flow and change the admin password.

## 11.1 Create Maven repository

- In Nexus: Settings/Repositories -> Create repository.
- Choose maven2 (hosted).
- Name it exactly maven-releases because Jenkinsfile uses this name.
- Choose a suitable Version policy such as Release.
- Save.

## 11.2 Create Docker hosted registry

- Create a docker (hosted) repository.
- Use repository name such as devshop-docker if desired.
- Set HTTP connector port to 8082 because Jenkinsfile uses NEXUS_DOCKER_REPO='8082'.
- Enable deployment/write permission for the Jenkins user.
- Save.

**Important:** The Jenkinsfile pushes to &lt;NEXUS_HOST&gt;:8082. The Nexus Docker repository must therefore listen on HTTP port 8082.

## 11.3 Create a non-admin Jenkins Nexus user

Create a dedicated user for CI/CD. Give only the Maven/Docker repository permissions required by this project. Do not use the Nexus admin account in Jenkins.

# 12\. Phase 9 — Configure Jenkins

WORK ON: jenkins-worker through its public IP.

http://&lt;JENKINS_PUBLIC_IP&gt;:8080

Retrieve the initial administrator password if needed:

ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@&lt;JENKINS_PUBLIC_IP&gt;  
sudo cat /var/lib/jenkins/secrets/initialAdminPassword

## 12.1 Install/configure plugins

Install the plugins represented by jenkins/plugins.txt, especially Pipeline, Git/GitHub, Credentials Binding, Docker Pipeline, Kubernetes CLI, and Maven support. The exact plugin installation UI may vary.

## 12.2 Add Jenkins labels

Built-In Node labels:  
jenkins maven docker

## 12.3 Add Jenkins credentials

- nexus-host — Secret text containing the Nexus host/IP only, e.g. 10.x.x.x or the reachable Nexus IP/hostname.
- nexus-docker — Username/password for the Nexus Docker repository.
- kubeconfig — Secret file containing the Kubernetes admin kubeconfig.

**Credential IDs:** The IDs must exactly be nexus-host, nexus-docker and kubeconfig because Jenkinsfile refers to those IDs.

## 12.4 Securely obtain kubeconfig

On control-plane, the kubeconfig is /etc/kubernetes/admin.conf. Copy it securely to your PC and upload it into Jenkins Credentials as a Secret file. Do not commit it.

\# On control-plane:  
sudo cp /etc/kubernetes/admin.conf /home/ubuntu/devshop-kubeconfig  
sudo chown ubuntu:ubuntu /home/ubuntu/devshop-kubeconfig  
chmod 600 /home/ubuntu/devshop-kubeconfig  
<br/>\# Securely transfer it to your PC, then upload as Jenkins secret file.  
\# After upload, delete temporary copies when no longer needed.

**Security:** admin.conf gives cluster-admin-level access. Treat it like a password.

# 13\. Phase 10 — Create Jenkins Pipeline

WORK ON: Jenkins UI. Create a Pipeline job connected to your GitHub repository. Use the Jenkinsfile from the repository.

- New Item -> Pipeline.
- Configure Git repository URL and credentials if the repository is private.
- Choose Pipeline script from SCM.
- SCM = Git.
- Set the repository URL and branch, normally \*/main.
- Script Path = jenkins/Jenkinsfile.
- Save.

## 13.1 Understand every Jenkins stage

**Checkout —** Runs on the maven-labeled Jenkins controller and downloads the repository.

**Build and Test —** Runs mvn clean test package inside application/. This creates target/devshop.jar.

**Publish Maven Artifact —** Deploys the Maven artifact to Nexus maven-releases.

**Docker Build —** Builds the application image using application/Dockerfile.

**Docker Push —** Logs into Nexus Docker registry on port 8082 and pushes the image tagged with BUILD_NUMBER.

**Deploy to Kubernetes —** Loads the kubeconfig credential, applies namespace/config/service/HPA, replaces the image placeholder and waits for rollout.

# 14\. Phase 11 — Prepare Kubernetes Application Configuration

WORK ON: control-plane for kubectl commands; edit repository files on your development machine and commit them to GitHub.

## 14.1 Create secret.yaml from example

cd kubernetes  
cp secret.yaml.example secret.yaml  
nano secret.yaml

Set the same RDS username/password that Terraform created. Do not commit secret.yaml.

## 14.2 Set the RDS endpoint in ConfigMap

Replace REPLACE_WITH_RDS_ENDPOINT with the Terraform rds_endpoint value. The final URL must look like:

SPRING_DATASOURCE_URL: "jdbc:mysql://devshop-mysql.xxxxxxxxxxxx.ap-south-1.rds.amazonaws.com:3306/devshop"

## 14.3 Verify the Spring Boot health endpoint

The application implements GET /api/health and returns status UP. The ALB target group and Kubernetes probes both depend on this endpoint.

curl http://&lt;NODE_OR_ALB_ADDRESS&gt;/api/health

**Database requirement:** Spring Boot startup can fail if RDS is unreachable or credentials are wrong. RDS is private and accepts MySQL only from the Kubernetes security group.

# 15\. Phase 12 — Test RDS Connectivity BEFORE blaming Jenkins

WORK ON: a Kubernetes worker or temporary debug pod. RDS is not supposed to be publicly reachable.

kubectl run mysql-client --rm -it --restart=Never --image=mysql:8.0 -- mysql -h &lt;RDS_ENDPOINT&gt; -P 3306 -u devshop -p

If this cannot connect, check the RDS security group, Kubernetes security group, RDS subnet group, credentials and endpoint. Do not make RDS public just to make the test pass.

**Common timeout cause:** A TCP 110 timeout usually means the network path/security group is blocking access, not that the MySQL username/password is wrong.

# 16\. Phase 13 — First Jenkins Run

WORK ON: Jenkins UI. Push the corrected project to GitHub and run the pipeline.

git status  
git add .  
git commit -m "Prepare DevShop no-Ansible-worker deployment"  
git push origin main

Watch the stages in order. If a stage fails, fix that stage before rerunning.

## 16.1 Build/Test failure

cd application  
./mvnw test  
\# or  
mvn test

The project uses Spring Boot 3.5.5, Java 21 and MySQL connector. If tests try to create a database connection, verify the test configuration and avoid requiring live RDS for unit tests.

## 16.2 Docker failure

docker version  
docker ps  
sudo systemctl status docker  
sudo -u jenkins docker version

**Permission issue:** The Jenkins user is added to the docker group. Restarting Jenkins is required after group membership changes; a new shell/session may also be needed.

# 17\. Phase 14 — Verify Kubernetes Deployment

WORK ON: control-plane.

kubectl get ns  
kubectl -n devshop get configmap,secret,service,deployment,hpa,pods  
kubectl -n devshop get pods -o wide  
kubectl -n devshop rollout status deployment/devshop  
kubectl -n devshop describe deployment devshop

## 17.1 Test from inside the cluster

kubectl -n devshop run curl-test --rm -it --restart=Never --image=curlimages/curl -- curl <http://devshop:8080/api/health>

## 17.2 Test NodePort

curl http://&lt;ANY_K8S_NODE_PUBLIC_IP&gt;:30080/api/health

Because the Service is NodePort 30080, Kubernetes exposes the service on each node. The ALB target group also points to port 30080.

# 18\. Phase 15 — Verify ALB

WORK ON: your PC/browser.

terraform output alb_dns_name  
curl http://&lt;ALB_DNS_NAME&gt;/api/health  
curl http://&lt;ALB_DNS_NAME&gt;/

Expected health response:

{"status":"UP"}

Expected home response:

{"application":"devshop","status":"running"}

**If ALB is unhealthy:** Check target group health, security group port 30080 access, kube-proxy/NodePort behavior, and that /api/health returns HTTP 200.

# 19\. Phase 16 — Optional Route 53

WORK ON: Terraform machine (PC initially; terraform-server later) and your DNS registrar.

- Have a public Route 53 hosted zone for your domain.
- Set domain_name to the hosted-zone domain, for example example.com (not app.example.com).
- Run terraform plan and apply.
- Terraform creates app.example.com as an alias to the ALB.
- If your domain is registered at GoDaddy, update its nameservers to the Route 53 hosted zone's four nameservers if you want Route 53 to be authoritative.
- Wait for DNS propagation, then test <http://app.example.com/api/health>.

**GoDaddy warning:** Do not enter a URL such as http://... into a nameserver field. Nameserver fields require hostname values supplied by Route 53.

# 20\. Phase 17 — End-to-End Test

1. Open the application through the ALB or Route 53 name.
2. Call /api/health and confirm status UP.
3. Check kubectl -n devshop get pods and confirm pods are Running/Ready.
4. Check kubectl -n devshop get hpa and kubectl top pods/nodes.
5. Change a small application response, commit and push to main.
6. Confirm GitHub webhook triggers Jenkins.
7. Confirm a new BUILD_NUMBER image is pushed to Nexus.
8. Confirm Kubernetes performs a rolling update.
9. Confirm the new response is visible through the ALB.

# 21\. Troubleshooting — Exact Problems Likely in This Project

**Terraform fails with worker index/out-of-range —** Set worker_count=4 because local.node_names contains four names.

**Ansible says 'when is not a valid attribute for a Play' —** Move the condition into a task using include_role, as shown in Phase 1.2.

**No package matching kubelet/kubeadm/kubectl —** Add the pkgs.k8s.io v1.33 repository before apt install. Then apt update.

**Jenkins apt NO_PUBKEY / repository not signed —** Correct the Jenkins key/repository; do not disable signature verification.

**kubectl label node JENKINS_NODE not found —** Use the real node name from kubectl get nodes. The names are normally EC2 hostname/node names, not the Terraform Name tag.

**Jenkins queues forever for maven/docker/jenkins —** Label the Jenkins built-in controller with all three labels, or change the Jenkinsfile agents.

**Nexus 8082 connection refused —** The Docker hosted repository must have an HTTP connector on port 8082.

**Docker login denied —** Use the dedicated Nexus Docker user and ensure that user can push to the hosted Docker repository.

**ImagePullBackOff in Kubernetes —** Check image name, Nexus registry reachability from workers, credentials/imagePullSecret if the Nexus registry requires authentication, and whether Nexus is configured for the chosen HTTP registry.

**RDS connection timeout —** Check RDS SG inbound 3306 from Kubernetes SG; verify endpoint and private routing. Do not make RDS public just to solve a timeout.

**Spring Boot CrashLoopBackOff —** kubectl logs -n devshop deployment/devshop. Most likely database endpoint/credentials/network or application startup issue.

**HPA has unknown CPU —** Install metrics-server and verify kubectl top nodes/pods.

**ALB target unhealthy —** Check NodePort 30080, /api/health, target group health, security groups and that at least one application pod is Ready.

**Route 53 hosted zone not found —** The zone must exist in Route 53 and domain_name must exactly match the public hosted zone name.

# 22\. Useful Diagnostic Commands

\# Kubernetes  
kubectl get nodes -o wide  
kubectl get pods -A  
kubectl -n devshop get all  
kubectl -n devshop describe pod &lt;POD&gt;  
kubectl -n devshop logs &lt;POD&gt;  
kubectl -n devshop get events --sort-by=.lastTimestamp  
<br/>\# Service / NodePort  
kubectl -n devshop get svc devshop  
curl http://&lt;NODE_IP&gt;:30080/api/health  
<br/>\# RDS-related application logs  
kubectl -n devshop logs deployment/devshop  
<br/>\# Docker/Nexus on nexus-worker  
sudo docker ps  
sudo docker logs nexus --tail 100  
<br/>\# Jenkins  
sudo systemctl status jenkins  
sudo journalctl -u jenkins -n 100 --no-pager  
<br/>\# Kubernetes node services  
sudo systemctl status kubelet  
sudo journalctl -u kubelet -n 100 --no-pager  
sudo systemctl status containerd  
sudo cat /etc/containerd/config.toml  
<br/>\# Terraform  
terraform validate  
terraform plan  
terraform output

# 23\. Security Rules You Must Follow

- Never commit terraform.tfvars.
- Never commit .pem private keys.
- Never commit kubernetes/secret.yaml.
- Never commit kubeconfig/admin.conf.
- Never put an RDS password in GitHub, Jenkinsfile, ConfigMap or Docker image.
- Keep RDS publicly_accessible=false.
- Keep SSH restricted to admin_cidr.
- Do not open RDS 3306 to 0.0.0.0/0.
- Do not use the Nexus admin account for Jenkins.
- Do not disable apt/GPG signature verification.
- Use HTTPS/TLS for Jenkins, Nexus, ALB and the application in a production implementation.
- Use AWS Secrets Manager rather than Terraform plaintext variables for production database credentials.
- Use a remote, locked Terraform state backend for production.

# 24\. Final Verification Checklist

- ☐ AWS identity works with aws sts get-caller-identity.
- ☐ Terraform init/validate/plan/apply succeeds.
- ☐ worker_count=4 and exactly four Kubernetes workers exist.
- ☐ ansible-server is NOT in Kubernetes worker groups.
- ☐ ansible all -m ping succeeds.
- ☐ Ansible common/Docker provisioning succeeds.
- ☐ Kubernetes repository is configured before kubelet/kubeadm/kubectl installation.
- ☐ kubeadm cluster is initialized and all nodes are Ready.
- ☐ Flannel is Running.
- ☐ metrics-server is Running and kubectl top works.
- ☐ Nexus is accessible on :8081.
- ☐ Nexus Maven repository is named maven-releases.
- ☐ Nexus Docker hosted repository listens on :8082.
- ☐ Jenkins is accessible on :8080.
- ☐ Jenkins controller has labels jenkins, maven and docker.
- ☐ Jenkins credentials IDs exactly match nexus-host, nexus-docker and kubeconfig.
- ☐ RDS endpoint is placed in ConfigMap and credentials are in Secret.
- ☐ DevShop deployment has 2 Ready replicas initially.
- ☐ NodePort 30080 responds to /api/health.
- ☐ ALB target group is healthy.
- ☐ ALB /api/health returns HTTP 200.
- ☐ Route 53 works if enabled.
- ☐ Changing code in GitHub triggers Jenkins and produces a new image/deployment.

# 25\. Recommended Execution Order — One-Line Version

1\. Your PC: install tools + AWS key  
2\. Your PC: fix project issues listed in Phase 1  
3\. Your PC: terraform init/validate/plan/apply  
4\. Your PC: save Terraform outputs  
5\. ansible-server: install Ansible + Docker collection  
6\. ansible-server: create inventory + SSH key configuration  
7\. ansible-server: ansible all -m ping  
8\. ansible-server: run site.yml  
9\. ansible-server: run kubernetes.yml  
10\. control-plane: verify nodes/pods  
11\. control-plane: install metrics-server  
12\. nexus-worker: finish Nexus configuration  
13\. jenkins-worker: finish Jenkins configuration  
14\. Jenkins: add nexus-host, nexus-docker, kubeconfig credentials  
15\. Jenkins: label controller jenkins/maven/docker  
16\. GitHub/Jenkins: create Pipeline from jenkins/Jenkinsfile  
17\. Kubernetes config: set RDS endpoint + Secret  
18\. GitHub: commit/push  
19\. Jenkins: Build -> Test -> Maven -> Docker -> Deploy  
20\. control-plane: verify rollout  
21\. PC: verify NodePort  
22\. PC: verify ALB  
23\. Optional: Route 53  
24\. Repeat with a code change to prove CI/CD works

# 26\. Important Project-Specific Notes

The archive is a learning/demo platform rather than a hardened production system. In particular, the supplied RDS password is passed to Terraform as a sensitive variable but can still exist in Terraform state; Nexus is initially exposed by public EC2 IP/ports; the ALB is HTTP-only; and the Kubernetes cluster is self-managed on public-subnet EC2 instances. These are acceptable learning-project choices only if the environment is controlled. For production, use private subnets for cluster nodes where practical, TLS, Secrets Manager, hardened security groups, remote Terraform state, imagePullSecrets/private registry access, backups, monitoring and least-privilege IAM.

# 27\. Files You Will Work With Most

| File                                                  | Why it matters                                            |
| ----------------------------------------------------- | --------------------------------------------------------- |
| terraform/terraform.tfvars                            | Your private infrastructure inputs; never commit.         |
| terraform/ec2.tf                                      | Defines management, control-plane and four workers.       |
| terraform/security_groups.tf                          | Defines SSH/Kubernetes/ALB/RDS traffic.                   |
| terraform/rds.tf                                      | Defines private MySQL.                                    |
| terraform/alb.tf                                      | Defines public ALB -> NodePort.                           |
| ansible/inventory/hosts.ini                           | Maps IPs and worker roles; never commit.                  |
| ansible/site.yml                                      | Installs common/Docker/Java/Jenkins/Nexus.                |
| ansible/kubernetes.yml                                | Creates and joins the Kubernetes cluster.                 |
| ansible/roles/kubernetes/tasks/main.yml               | Kubernetes package installation; repository fix required. |
| jenkins/Jenkinsfile                                   | CI/CD pipeline.                                           |
| kubernetes/configmap.yaml                             | RDS JDBC URL.                                             |
| kubernetes/secret.yaml                                | RDS username/password; never commit.                      |
| kubernetes/deployment.yaml                            | DevShop pods and probes.                                  |
| kubernetes/service.yaml                               | NodePort 30080.                                           |
| kubernetes/hpa.yaml                                   | Autoscaling 2-5 replicas.                                 |
| application/pom.xml                                   | Java 21/Spring Boot/Maven dependencies.                   |
| application/Dockerfile                                | Builds the runtime image.                                 |
| application/src/main/resources/application.properties | Spring Boot datasource/environment configuration.         |

**Finish line:** Do not consider the project complete just because Terraform and Ansible finish. The real success test is: GitHub push -> Jenkins pipeline -> Maven test -> Nexus artifact -> Docker image -> Nexus registry -> Kubernetes rolling deployment -> healthy pods -> ALB -> /api/health -> RDS-backed application.