# DevShop AWS DevOps Platform — No Ansible Worker

End-to-end learning project using AWS, Terraform, Ansible, self-managed Kubernetes on EC2, Jenkins, Maven, Nexus, Docker, RDS, S3, ALB and Route53.

## Important architecture decision

There is **NO Ansible worker EC2 instance**.

Ansible is installed and executed from the dedicated `ansible-server`. The Jenkins EC2 instance is the Jenkins controller and performs the CI/CD deployment to Kubernetes using a Jenkins `kubeconfig` credential. This removes the old `ansible` Jenkins agent/deployment stage.

### Final workflow

GitHub
→ Jenkins
→ Maven build + test
→ Nexus Maven repository
→ Docker build
→ Nexus Docker registry
→ Jenkins + kubectl
→ self-managed Kubernetes
→ NodePort
→ AWS ALB
→ Route53 (optional)
→ Spring Boot
→ private RDS MySQL

## EC2 nodes

Terraform creates:

1. `terraform-server` — Terraform execution/management host.
2. `ansible-server` — Ansible control host; **not a Kubernetes worker**.
3. `k8s-control-plane` — Kubernetes control plane.
4. `jenkins-worker` — Jenkins controller, Docker, Maven and kubectl.
5. `maven-worker` — Java/Maven environment for learning or future Jenkins agent use.
6. `nexus-worker` — Nexus Repository Docker container.
7. `web-worker` — Kubernetes application worker.

The default `worker_count` is **4**: Jenkins, Maven, Nexus and Web. There is no `ansible-worker`.

## Build order

1. Create/use an AWS IAM identity with permission to create the project resources.
2. Create an EC2 key pair.
3. Find your public IP and set `admin_cidr`.
4. Configure `terraform/terraform.tfvars`.
5. Run Terraform: `init`, `fmt`, `validate`, `plan`, `apply`.
6. Capture Terraform outputs.
7. Create `ansible/inventory/hosts.ini`.
8. Set the correct SSH private-key path in `ansible/ansible.cfg`.
9. Install Ansible and the Docker collection on the Ansible server/local admin machine.
10. Run `ansible-playbook site.yml`.
11. Run `ansible-playbook kubernetes.yml`.
12. Verify Kubernetes nodes and pods.
13. Copy the control-plane kubeconfig securely to Jenkins Credentials as a secret file named `kubeconfig`.
14. Configure Nexus Maven and Docker hosted repositories.
15. Configure Jenkins credentials: `nexus-host`, `nexus-docker`, and `kubeconfig`.
16. Create a Jenkins Pipeline from `jenkins/Jenkinsfile`.
17. Configure GitHub webhook to Jenkins.
18. Push to `main`.
19. Jenkins builds/tests, publishes the Maven artifact, builds/pushes the Docker image, and deploys to Kubernetes.
20. Verify the ALB URL and `/api/health`.

## Security

Never commit `terraform.tfvars`, `ansible/inventory/hosts.ini`, kubeconfig files, private keys, or real passwords.

For production, replace plaintext RDS credentials with AWS Secrets Manager and use HTTPS/TLS for Nexus, Jenkins and the application.
