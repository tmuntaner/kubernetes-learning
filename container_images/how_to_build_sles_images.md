# Building SLES Containers

Building a SLES container differs from a traditional server, but it’s worthwhile to learn its nuances. The fundamental difference is that instead of using [SUSEConnect](https://github.com/suse/connect), it uses [container-suse-connect](https://github.com/SUSE/container-suseconnect). The container team optimized the latter tool for a container workflow and it simplifies the authoring process.

## Generate Your SCCcredentials

`container-suse-connect` requires a file `SCCcredentials` to communicate with SCC. You can either get this off a registered SLES machine, or if on another OS (e.g. openSUSE), you can generate one with docker.

**Tip:** `SUSEConnect` can also register recent versions of openSUSE Leap. This makes it an easy target to generate a `SCCcredentials` file.

```bash
touch SCCcredentials
docker run --rm -it --mount type=bind,source="$(pwd)"/SCCcredentials,target=/SCCcredentials opensuse/leap:15.2 /bin/bash
```

```bash
zypper --non-interactive in SUSEConnect
SUSEConnect -r YOUR_EMPLOYEE_REGCODE
cat /etc/zypp/credentials.d/SCCcredentials > /SCCcredentials
```

## Build and Update a Simple Container

Create a `Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:experimental

FROM registry.suse.com/suse/sle15:15.2

RUN --mount=type=secret,id=SCCcredentials,required \
    zypper --non-interactive up
```

And then build it:

```bash
DOCKER_BUILDKIT=1 docker build --pull --secret id=SCCcredentials,src=SCCcredentials -t my-awesome-image .
```

## Build with Modules

The previous container could access SLES repositories, but only the repositories from the base modules. If you need to install something like  `nginx`, you'll need access to more.

If we check the [SUSE Package Search](https://scc.suse.com/packages?name=SUSE%20Linux%20Enterprise%20Server&version=15.2&arch=x86_64&query=nginx&module=1955) tool, we see that it's located under the Server Applications Module. This module doesn't come as a default, so we'll need to specify that we want it.

First, we'll need to know the module's identifier for `container-suseconnect`. Bellow, is a command which lists all the available modules for our regcode:

```bash
docker run --rm -it --mount type=bind,source="$(pwd)"/SCCcredentials,target=/etc/zypp/credentials.d/SCCcredentials registry.suse.com/suse/sle15:15.2 /usr/bin/container-suseconnect lm
```

From this command, we can find our module:

```text
...
Name: Server Applications Module
Identifier: sle-module-server-applications
Recommended: true
...
```

Let's use this to install nginx in our `Dockerfile`:

**Notes:**
* You can provide modules as a comma separated list in the environmental variable `ADDITIONAL_MODULES`.

```dockerfile
# syntax=docker/dockerfile:experimental

FROM registry.suse.com/suse/sle15:15.2

ENV ADDITIONAL_MODULES sle-module-server-applications
RUN --mount=type=secret,id=SCCcredentials,required \
    zypper --non-interactive up && \
    zypper --non-interactive in nginx
```
