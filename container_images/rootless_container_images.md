# Rootless Container Images

If we want to minimize our attack surface, one of the first tasks to do is run an application as a user other than root. This can help limit an attackers reach, because we scope the user's permissions to the application.

## Build a Rootless Container Image

In the container build process, you'll want to create both a user and group, and specify the image's user with `USER`. Don't worry about the user/group id, you can specify them in kubernetes with a [Pod Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/).

```dockerfile
FROM opensuse/tumbleweed:latest

# Install Dependencies
RUN zypper --non-interactive in git go shadow

# Build the binary
RUN go get github.com/tmuntaner/echo-server/cmd/echo-server && \
    mv /root/go/bin/echo-server /usr/local/bin

# Create the non-root user
RUN groupadd -r echo-server && \
    useradd -r -g echo-server -s /sbin/nologin -c "Docker image user" echo-server

# Specify that we want to run as a user
USER echo-server

EXPOSE 8080
CMD ["/usr/local/bin/echo-server"]
```

## Pod Security Context in Kubernetes

Kubernetes gives you further control on the user/group running your application. This is done through the Pod Security Context, where you specify the user/group context for your entire pod or just a single container.

**Options for Pod Security Context:**

* `runAsUser` - The uid (user id) for the container process.
* `runAsGroup` - The gid (group id) for the container process.
* `fsGroup` - An additional group used for interacting with the file system. Please note that this cannot be set for a single container, but it can be useful in having a shared group in a pod for filesystem access.

### For an Entire Pod

```yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo-server
  template:
    metadata:
      labels:
        app: echo-server
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 3000
        fsGroup: 2000
      containers:
        - name: echo-server
          image: tmuntaner/echo-server
          ports:
            - containerPort: 8080
              name: http
```

### For a Single Container

```yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo-server
  template:
    metadata:
      labels:
        app: echo-server
    spec:
      securityContext:
        fsGroup: 2000
      containers:
        - name: echo-server
          image: tmuntaner/echo-server
          securityContext:
            runAsUser: 1000
            runAsGroup: 3000
          ports:
            - containerPort: 8080
              name: http
```
