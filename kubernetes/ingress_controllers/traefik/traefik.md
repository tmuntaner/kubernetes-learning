# The Traefik Ingress Controller

Traefik is an ingress controller made to be a modern HTTP reverse proxy that simplifies the deployment of microservices. With a rich feature stack, it has become popular as an easy to use kubernetes ingress controller, and the default in [k3s](https://k3s.io/).

## Prerequisites

To follow along with this guide, you'll need a kubernetes cluster with traefik installed. If you don't have one yet, [k3s](https://k3s.io/) is a great project to create a development cluster with traefik installed by default. Otherwise, visit the official install [guide](https://doc.traefik.io/traefik/getting-started/install-traefik/).

To use HTTPS, you'll also need to install `cert-manager`:

```bash
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.2.0/cert-manager.yaml
```

## Example Kubernetes YAML File

Please follow along with this guide to create your own `traefik-example.yml` file. The guide eventually builds up to the example [traefik-example.yml](traefik-example.yml).

## Deployment Setup

Before we work with an ingress, we'll need to have a service which it points to. For this, we'll use the `echoserver`. This is a simple service without external dependencies which returns the HTTP request back to the client.

1. Create the test namespace `traefik-example`:

```bash
kubectl create namespace traefik-example
```

2. Create a file `traefik-example.yml` and fill it with the following contents:

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
```

3. Use a port forward to expose the service to localhost:

```bash
kubectl -n traefik-example port-forward service/hello-node :8080
```
```text
Forwarding from 127.0.0.1:43319 -> 8080
Forwarding from [::1]:43319 -> 8080
```

**Notes:**
* This port forward is necessary because we haven't exposed this service to traefik as an ingress yet.
* `kubectl` will assign your service a random local port. It will probably be different from the example output.

4. Curl your port-forwarded service to verify that it works:

**Note:** Be sure to use the forwarded port from the previous step.

```bash
curl http://localhost:43319
```
```text
CLIENT VALUES:
client_address=127.0.0.1
command=GET
real path=/
query=nil
request_version=1.1
request_uri=http://localhost:8080/

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
host=localhost:43319
user-agent=curl/7.74.0
BODY:
-no body in request-
```

## Ingress

To move beyond a port forward, we'll need an `Ingress` resource, however, you'll need a domain to associate with it. For simplicity, we'll use the domain `hello-node.internal`. Because the TLD `.internal` is a [private DNS namespace](https://tools.ietf.org/html/rfc6762#appendix-G), you can safely edit `/etc/hosts` to use it within your computer.

1. Edit the file `/etc/hosts` and add assign `hello-node.internal` to `127.0.0.1`:

```bash
sudo vim /etc/hosts
```
```text
127.0.0.1       hello-node.internal
```

2. Add the ingress definition to your `traefik-example.yml`:

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-node-ingress
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: hello-node.internal
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: hello-node
              port:
                number: 8080
```

3. Apply the ingress changes:

```bash
kubectl -n traefik-example apply -f traefik-example.yml
```

4. Use curl to test your ingress:

```bash
curl http://hello-node.internal
```
```text
CLIENT VALUES:
client_address=10.42.0.4
command=GET
real path=/
query=nil
request_version=1.1
request_uri=http://hello-node.internal:8080/

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
accept-encoding=gzip
host=hello-node.internal
user-agent=curl/7.74.0
x-forwarded-for=10.42.0.7
x-forwarded-host=hello-node.internal
x-forwarded-port=80
x-forwarded-proto=http
x-forwarded-server=traefik-6f9cbd9bd4-qt9dc
x-real-ip=10.42.0.7
BODY:
-no body in request-
```

**Note:** *If you have trouble connecting to the ingress, please check your firewall. It's possible that `firewalld` could interfere with the kubernetes networking.*

## Using Ingress with self-signed TLS

**Note:** *Do not use these steps for a production deployment. Please use either a signed certificate or let's encrypt.*

1. Before you can add TLS to your ingress, you'll need to create a self-signed certificate issuer. Add the following block to`traefik-example.yml`:

```yaml
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: traefik-example
spec:
  selfSigned: {}
```

2. Edit your previously created ingress to add TLS:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-node-ingress
  annotations:
    kubernetes.io/ingress.class: traefik
    cert-manager.io/issuer: selfsigned-issuer
spec:
  rules:
    - host: hello-node.internal
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: hello-node
                port:
                  number: 8080
  tls:
    - hosts:
        - hello-node.internal
      secretName: hello-node-tls
```

3. Apply your changes to the cluster:

```bash
kubectl -n traefik-example apply -f traefik-example.yml
```

4. Verify that `https://hello-node.internal` works:

```bash
curl --insecure https://hello-node.internal/
```
```text
CLIENT VALUES:
client_address=10.42.0.4
command=GET
real path=/
query=nil
request_version=1.1
request_uri=http://hello-node.internal:8080/

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
accept-encoding=gzip
host=hello-node.internal
user-agent=curl/7.74.0
x-forwarded-for=10.42.0.7
x-forwarded-host=hello-node.internal
x-forwarded-port=443
x-forwarded-proto=https
x-forwarded-server=traefik-6f9cbd9bd4-qt9dc
x-real-ip=10.42.0.7
BODY:
-no body in request-
```

**Note:**

* We're using `--insecure` because the self-signed domain shouldn't be trusted by your computer yet. To further inspect the certificate, you can use `openssl s_client -connect hello-node.internal:443 | openssl x509 -noout -text`.

## HTTP to HTTPS Redirects

Currently, both `http://hello-node.internal` and `https://hello-node.internal` work. This is great for development, however, it's a good practice to redirect HTTP to HTTPS. Let's edit our ingress to do redirect all HTTP calls to HTTPS.

1. Edit your ingress resource in `traefik-example.yml` and add the `ingress.kubernetes.io/ssl-redirect: "true"` annotation:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-node-ingress
  annotations:
    kubernetes.io/ingress.class: traefik
    cert-manager.io/issuer: selfsigned-issuer
    ingress.kubernetes.io/ssl-redirect: "true"
spec:
  rules:
    - host: hello-node.internal
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: hello-node
                port:
                  number: 8080
  tls:
    - hosts:
        - hello-node.internal
      secretName: hello-node-tls
```

2. Apply your changes to the cluster:

```bash
kubectl -n traefik-example apply -f traefik-example.yml
```

3. Verify that the redirect works with curl.

Check the redirect headers:
```bash
curl -I http://hello-node.internal/
```
```text
HTTP/1.1 301 Moved Permanently
Content-Type: text/html; charset=utf-8
Location: https://hello-node.internal/
Vary: Accept-Encoding
Date: Tue, 09 Mar 2021 15:51:36 GMT
```

Try to curl against HTTP:
```bash
curl http://hello-node.internal/
```
```text
<a href="https://hello-node.internal/">Moved Permanently</a>.
```

Try to curl against HTTPS:
```bash
curl --insecure https://hello-node.internal/
```
```text
CLIENT VALUES:
client_address=10.42.0.4
command=GET
real path=/
query=nil
request_version=1.1
request_uri=http://hello-node.internal:8080/

SERVER VALUES:
server_version=nginx: 1.10.0 - lua: 10001

HEADERS RECEIVED:
accept=*/*
accept-encoding=gzip
host=hello-node.internal
user-agent=curl/7.74.0
x-forwarded-for=10.42.0.7
x-forwarded-host=hello-node.internal
x-forwarded-port=443
x-forwarded-proto=https
x-forwarded-server=traefik-6f9cbd9bd4-qt9dc
x-real-ip=10.42.0.7
BODY:
-no body in request-
```

This should cover enough to get you started with traefik. For more detailed information, you can visit its [documentation](https://doc.traefik.io/traefik/).
