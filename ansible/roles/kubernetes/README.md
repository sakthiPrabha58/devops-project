Kubernetes is intentionally self-managed with kubeadm rather than EKS. The playbook installs kubelet/kubeadm/kubectl, initializes one control plane, installs Flannel and joins the five workers.

For production, use a highly available control plane, private worker subnets, restricted security groups, TLS management, secrets management, monitoring and backups.
