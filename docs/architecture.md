# Architecture — No Ansible Worker

## Components

- **Terraform server**: runs Terraform and creates AWS infrastructure.
- **Ansible server**: runs Ansible. It is the only Ansible control node and is not part of Kubernetes.
- **Jenkins**: CI/CD controller. It has Java, Maven, Docker and kubectl.
- **Maven worker**: optional dedicated Maven environment for future Jenkins-agent use.
- **Nexus worker**: runs Nexus Repository in Docker and stores Maven/Docker artifacts.
- **Kubernetes control plane**: manages the self-hosted Kubernetes cluster.
- **Web worker**: runs the DevShop application pods.
- **RDS MySQL**: private database.
- **S3**: private artifact/backup bucket.
- **ALB**: public HTTP entry point to the Kubernetes NodePort.
- **Route53**: optional DNS record `app.<domain>`.

## Deployment flow

1. Developer pushes Java source to GitHub.
2. GitHub webhook triggers Jenkins.
3. Jenkins checks out the source.
4. Maven compiles, tests and packages the Spring Boot application.
5. Jenkins deploys the Maven artifact to Nexus.
6. Jenkins builds the Docker image.
7. Jenkins authenticates to Nexus Docker registry and pushes the image.
8. Jenkins uses its stored kubeconfig and `kubectl` to deploy the new image.
9. Kubernetes performs a rolling update.
10. ALB sends traffic to the Kubernetes NodePort.
11. Pods expose Spring Boot on port 8080.
12. Spring Boot connects to private RDS MySQL using Kubernetes ConfigMap/Secret values.

## Important change

The old `ansible-worker` is removed completely. The Jenkins deployment stage no longer uses `agent { label 'ansible' }`; it runs on the Jenkins controller and uses kubectl directly.
