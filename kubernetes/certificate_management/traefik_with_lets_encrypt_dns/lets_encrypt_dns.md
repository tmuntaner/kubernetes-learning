# Taefik with Let's Encrypt DNS Validation

## Prerequisites

**Kubernetes Cluster:**

To follow along with this guide, you'll need a public facing kubernetes cluster.

**Traefik:**

We'll need traefik installed on the cluster as an ingress controller. Check with your cluster administrator has already it pre-installed, if not, you can install it with helm:

```bash
helm repo add traefik https://helm.traefik.io/traefik
helm repo update
helm install traefik traefik/traefik
```

**Cert-Manager:**

You'll need `cert-manager` installed on the cluster. Check with your cluster administrator has already it pre-installed, if not, you can install it with the following:

```bash
kubectl create namespace cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.3.1 \
  --set installCRDs=true
```

**Cert-Manager Permissions IAM Role:**

1. Create an IAM role for the `cert-manager` service account, see the example [terraform configuration](example.tf) for more information.
2. Add the following to your helm configuration.

```dockerfile
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: THE_IAM_ROLE_ARN_CREATED_IN_STEP_1
```

**Route53 Zone:**

Lastly, you'll want host your domain (or a specific subdomain as a zone) in Route53. Unfortunately, it's impossible to use a shared domain for all readers, so I'll host the zone `razorcrest.thomasmuntaner.com` on Route53.

**Domain:**

You'll want a public facing domain hosted on your Route53 zone above. I'll use the domain `hello-node.razorcrest.thomasmuntaner.com`.

To point your domain at the traefik ingress controller, you'll need to find the load balancer's `EXTERNAL-IP`.

```bash
kubectl get services -A
```

```text
NAMESPACE         NAME                       TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)                                                                      AGE
...
default           traefik                    LoadBalancer   10.100.229.224   **.eu-west-1.elb.amazonaws.com                                            80:30954/TCP,443:31038/TCP                                                   14s
```

Create a CNAME record with the value in `EXTERNAL-IP` and point it at your domain.

## Deployment Setup

Before we use Let's Encrypt, we'll need to have a service and a corresponding ingress. For this, we'll deploy an `echoserver`, a simple service without external dependencies which returns the HTTP request back to the client.

1. Create the test namespace `lets-encrypt`:

```bash
kubectl create namespace lets-encrypt
```

2. Create the service and the ingress yaml definition:

```bash
vim lets-encrypt-example.yml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-node
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-node
  template:
    metadata:
      labels:
        app: hello-node
    spec:
      containers:
        - name: echoserver
          image: tmuntaner/echo-server
          ports:
            - containerPort: 8080
              name: http
---
apiVersion: v1
kind: Service
metadata:
  name: hello-node
spec:
  ports:
    - port: 8080
  selector:
    app: hello-node
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: hello-node-ingress
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
    - host: hello-node.razorcrest.thomasmuntaner.com
      http:
        paths:
          - path: /
            backend:
              serviceName: hello-node
              servicePort: 8080
```

Apply the yaml definition in kubernetes to create your deployment:

```bash
kubectl -n traefik-example apply -f lets-encrypt-example.yml
```

3. You should now have a working deployment which the ingress exposes to the internet. Let's examine the ingress:

```bash
kubectl -n lets-encrypt get ingress
```

```text
NAME                 HOSTS                                      ADDRESS   PORTS   AGE
hello-node-ingress   hello-node.razorcrest.thomasmuntaner.com             80      2m3s
```

Let's curl against the domain to verify that it works:

```bash
curl http://hello-node.razorcrest.thomasmuntaner.com/echo
```

```text
URL: /echo
Method: GET
Protocol: HTTP/1.1

Headers:
Accept: */*
Accept-Encoding: gzip
User-Agent: curl/7.76.0
X-Forwarded-For: 172.31.6.124
X-Forwarded-Host: hello-node.razorcrest.thomasmuntaner.com
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Server: traefik-68974f9c4b-ljk94
X-Real-Ip: 172.31.6.124
```

If we use https, we get a response, but we also get a certificate mismatch.

```bash
curl https://hello-node.razorcrest.thomasmuntaner.com/echo
```

```text
curl: (60) SSL certificate problem: self signed certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
```

We can solve this with let's encrypt.

## Certificates with Let's Encrypt and DNS Solver

For the management of the certificate within our cluster, we'll use `cert-manager`. It interfaces with let's encrypt and handles the life-cycle of our certificate for us.

1. Let's define our `cert-manager` issuer and certificate by appending it to our yaml definition:

```bash
vim lets-encrypt-example.yml
```

```yaml
...
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-issuer
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-issuer-account-key
    solvers:
      - selector:
          dnsZones:
            - "razorcrest.thomasmuntaner.com"
        dns01:
          route53:
            region: eu-west-1
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: hello-node
spec:
  dnsNames:
    - hello-node.razorcrest.thomasmuntaner.com
  secretName: acme-web-hello-node-certificate
  issuerRef:
    name: letsencrypt-issuer
    kind: ClusterIssuer
```

**Note:**

* You can see `cert-manager` issuer's [documentation](https://cert-manager.io/docs/configuration/acme/http01/) for more details.

2. Let's now use our issuer by redefining our ingress.

```bash
vim lets-encrypt-example.yml
```

```yaml
...
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: hello-node-ingress
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/router.entrypoints: web, websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  rules:
    - host: hello-node.razorcrest.thomasmuntaner.com
      http:
        paths:
          - path: /
            backend:
              serviceName: hello-node
              servicePort: 8080
  tls:
    - hosts:
        - hello-node.razorcrest.thomasmuntaner.com
      secretName: acme-web-hello-node-certificate
...
```

3. Now let's apply our definition changes and test our ingress:

```bash
kubectl -n traefik-example apply -f lets-encrypt-example.yml
```

You should have a new valid https certificate.

```bash
curl https://hello-node.razorcrest.thomasmuntaner.com/echo
```

```text
URL: /echo
Method: GET
Protocol: HTTP/1.1

Headers:
Accept: */*
Accept-Encoding: gzip
User-Agent: curl/7.76.0
X-Forwarded-For: 172.31.6.124
X-Forwarded-Host: hello-node.razorcrest.thomasmuntaner.com
X-Forwarded-Port: 443
X-Forwarded-Proto: https
X-Forwarded-Server: traefik-68974f9c4b-ljk94
X-Real-Ip: 172.31.6.124
```

You can see a complete example yaml file at [lets-encrypt-example.yml](lets-encrypt-example.yml).
