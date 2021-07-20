# Kubernetes Learning

This is a notebook of my lessons learned while exploring kubernetes. Hopefully some of my notes can help you as well.

## Container Images

* [How to Build SLES Images](container_images/how_to_build_sles_images.md)
* [Multi-Stage Builds with Docker](container_images/multi_stage_builds_container_images.md)
* [Rootless Container Images](container_images/rootless_container_images.md)

## Kubernetes

### Secrets Management

* [Sealed Secrets](kubernetes/secrets_management/sealed_secrets.md)

### Ingress Controllers

Ingress controllers help expose your kubernetes services outside a cluster. They make their operators' lives easier by hiding the implementation details of reverse proxy configurations and certificates, leaving you to only configure an `Ingress` resource.

* [Traefik](kubernetes/ingress_controllers/traefik/traefik.md)

### Kubernetes in AWS (EKS)

* [IAM Roles in EKS Deployments](kubernetes/eks/eks_service_accounts.md)

### Certificate Management

* [Traefik with Let's Encrypt HTTP Verification](kubernetes/certificate_management/traefik_with_lets_encrypt_http/lets_encrypt_http.md)
* [Traefik with Let's Encrypt DNS Verification](kubernetes/certificate_management/traefik_with_lets_encrypt_http/lets_encrypt_dns.md)
