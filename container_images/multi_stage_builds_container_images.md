# Multi-Stage Builds Container Images

Does your docker container require build steps or external resources to create a final target image? It may be tempting to implement those steps outside your Dockerfile, but that isn't so advantageous.

Dockerfiles have a feature known as multi-stage builds. With it, a Dockerfile can use multiple container bases to build a final target image, allowing you to copy resources from one container to another.

This becomes useful when you require libraries, packages, and other non-runtime dependencies to build your image. In one image, you can have all the dependencies you want, and in the final image, you can copy the previous files and only install the dependencies you need for production runtime.

This may sound complicated, but it really isn't and could make your containers safer, more slim, simpler, and easier to maintain.

## A Simple Example

In this example, we'll build a simple golang webserver `echo-server` image from two build stages and two separate base operating systems: openSUSE Tumbleweed and Leap.

In the first build stage, we'll use openSUSE tumbleweed and install the necessary dependencies such as `go` and `git`. In this way, we can benefit from a newer `go` package version without the use of external zypper repositories.

In the second stage, the last stage definition so the final container, we'll use openSUSE Leap with the only dependency being the `echo-server` artifact built in the previous stage. When you distribute your image, you only distribute the smaller leap image, using only what is strictly necessary.

```dockerfile
# The initial build stage
FROM opensuse/tumbleweed:latest

RUN zypper --non-interactive in git go

RUN git clone https://github.com/tmuntaner/echo-server.git --depth 1 /build

WORKDIR /build

ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
RUN go build -a -tags netgo -ldflags '-extldflags "-static"' -o echo-server cmd/main.go

## The final stage and resulting image
FROM opensuse/leap:latest

COPY --from=0 /build/echo-server /usr/local/bin

RUN groupadd -r echo-server && \
    useradd -r -g echo-server -s /sbin/nologin -c "Docker image user" echo-server

USER echo-server

EXPOSE 8080

CMD ["/usr/local/bin/echo-server"]
```

If you found this example interesting, please see the [official documentation](https://docs.docker.com/develop/develop-images/multistage-build/) to find more options and explanations.
