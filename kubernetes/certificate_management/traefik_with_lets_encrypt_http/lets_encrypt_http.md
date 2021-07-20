# Taefik with Let's Encrypt HTTP Validation

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
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.2.0/cert-manager.yaml
```

**Domain:**

Lastly, you'll want to point a public domain at your Traefik ingress controller deployment. Unfortunately, it's impossible to use a shared domain for all readers, so I'll use a personal domain `hello-node.thomasmuntaner.com`. Be sure to replace its usage with a domain under your control.

To point your domain at the traefik install, first you'll need to find the load balancer's domain.

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
          image: k8s.gcr.io/echoserver:1.4
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
    - host: hello-node.thomasmuntaner.com
      http:
        paths:
          - path: /
            pathType: Prefix
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
NAME                 HOSTS                           ADDRESS   PORTS   AGE
hello-node-ingress   hello-node.thomasmuntaner.com             80      14m
```

Let's curl against the domain to verify that it works:

```bash
curl http://hello-node.thomasmuntaner.com
```

```text
CLIENT VALUES:
client_address=172.31.15.29
command=GET
real path=/
query=nil
request_version=1.1
request_uri=http://hello-node.thomasmuntaner.com:8080/

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
accept-encoding=gzip
host=hello-node.thomasmuntaner.com
user-agent=curl/7.75.0
x-forwarded-for=172.31.6.124
x-forwarded-host=hello-node.thomasmuntaner.com
x-forwarded-port=80
x-forwarded-proto=http
x-forwarded-server=traefik-68974f9c4b-ljk94
x-real-ip=172.31.6.124
BODY:
-no body in request-
```

If we use https, we get a response, but we also get a certificate mismatch.

```bash
curl https://hello-node.thomasmuntaner.com
```

```text
curl: (60) SSL certificate problem: self signed certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
```

We can solve this with let's encrypt.

## Traefik Ingress Certificates with Let's Encrypt

For the management of the certificate within our cluster, we'll use `cert-manager`. It interfaces with let's encrypt and handles the life-cycle of our certificate for us.

1. Let's define our `cert-manager` issuer by appending it to our yaml definition:

```bash
vim lets-encrypt-example.yml
```

```yaml
...
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: lets-encrypt-http
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: issuer-account-key
    solvers:
      - http01:
          ingress:
            class: traefik

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
    cert-manager.io/issuer: lets-encrypt-http
    kubernetes.io/tls-acme: "true"
    traefik.ingress.kubernetes.io/router.entrypoints: web, websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  rules:
    - host: hello-node.thomasmuntaner.com
      http:
        paths:
          - path: /
            backend:
              serviceName: hello-node
              servicePort: 8080

  tls:
    - hosts:
        - hello-node.thomasmuntaner.com
      secretName: hello-node-tls
...
```

3. Now let's apply our definition changes and test our ingress:

```bash
kubectl -n traefik-example apply -f lets-encrypt-example.yml
```

After about a minute or so, you should have a new valid https certificate.

```bash
curl https://hello-node.thomasmuntaner.com
```

```text
CLIENT VALUES:
client_address=172.31.15.29
command=GET
real path=/
query=nil
request_version=1.1
request_uri=http://hello-node.thomasmuntaner.com:8080/

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
accept-encoding=gzip
host=hello-node.thomasmuntaner.com
user-agent=curl/7.75.0
x-forwarded-for=172.31.6.124
x-forwarded-host=hello-node.thomasmuntaner.com
x-forwarded-port=443
x-forwarded-proto=https
x-forwarded-server=traefik-68974f9c4b-ljk94
x-real-ip=172.31.6.124
BODY:
-no body in request-
```

You can see a complete example yaml file at [lets-encrypt-example.yml](lets-encrypt-example.yml).
