# Sealed Secrets

[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) is a project from [bitnami](https://bitnami.com/) which takes the approach of encrypting kubernetes secrets, allowing you to store the encrypted artifact within a git repository.

Why would you do that?

Secrets in kubernetes are hard, and this product allows you to integrate them in your GitOps pipeline. As only the controller can decrypt your secrets, you can have the kubernetes yaml artifact with the rest of your deployment code with minimal risk.

The advantage of this tool is that you can simplify the deployment of your secrets. While it may not be as secure as a product like HashiCorp Vault, it reduces the operational risk of being unable to deploy applications if the service goes down.

## Getting Started

Before you move on, please check with your cluster operators to see whether they already installed the Sealed Secrets controller.

### For Cluster Operators

The following steps show how to install the sealed secrets project into your cluster with helm:

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets --namespace kube-system
```

### For Users

#### Prerequisites

To follow this guide, you’ll need to have the `kubeseal` binary. To assist in its adoption, we’ve packaged the binary in OBS for common SLES and openSUSE operating systems.

The OBS repositories are located at https://build.opensuse.org/repositories/home:tmuntan1:RazorCrest.

Here is an example install process for tumbleweed:

```bash
zypper ar https://download.opensuse.org/repositories/home:/tmuntan1:/RazorCrest/openSUSE_Tumbleweed/home:tmuntan1:RazorCrest.repo
zypper ref
zypper in sealed-secrets
```

#### Creating an Initial Secret

First, we’ll need to generate an example secret.

**Note:** *We’re using `--dry-run` while we create the secret to avoid creating it on the cluster.*

```bash
kubectl create namespace sealed-secrets-demo
echo -n “very secret” | kubectl create secret generic my-secret --namespace sealed-secrets-demo --dry-run --from-file=password=/dev/stdin -o yaml > my_secret.yaml
```

Our command should have created the following secret.

```yaml
apiVersion: v1
data:
  password: dmVyeSBzZWNyZXQ=
kind: Secret
metadata:
  creationTimestamp: null
  name: my-secret
  namespace: sealed-secrets-demo
```

Let’s verify that the secret doesn’t exist on the cluster yet:

**Note:** *Your output may differ from mine.*

```bash
kubectl -n sealed-secrets-demo get secrets
```
```text
NAME                  TYPE                                  DATA   AGE
default-token-47ntx   kubernetes.io/service-account-token   3      103s
```

It’s not there, so let’s continue and create the encrypted artifact with the `kubeseal` client.

The client will contact the kubernetes cluster, receive its public encryption certificate, encrypt against the key, and save its contents in a kubernetes yaml file. You can also provide the public certificate yourself, but we won’t cover that in this tutorial.

```bash
kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system --format yaml < my_secret.yaml > my_sealed_secret.yaml
```
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  creationTimestamp: null
  name: my-secret
  namespace: sealed-secrets-demo
spec:
  encryptedData:
    password: AgAr8NT4i5r3belKGlL5WP7a6m3+wIAAAuFTTQP89cWjOJhOwtTMKYNBcSVGND78TA9ukVkPRp1qDyrwAmn1kSzLIqWqIvSFZGVGHiBYqzbL36kItEUI/lTPA5M6VkT0hP1LB4VPb5CgdTBnPmZykWXPcvvC6kFj0dK/S8sxMphNlsylS/C1+IAJgnECSYiq0Qu3gIhX+4rrtt3sOh0Sq4x4fN2olks57x0XCtgD/SCm8KtrlFHJZgU2jKFRNxAR8et20z9gzw/GgB7v/eZz98vMxBvp8kLhUWASJ1wffGim5SEAqwGO4tNzSDOU9QN7zeSd7Q+0bB+wxH1NnqJyNM54DHh6mj4U57D5Hg+OIjonnMIqev6lF/lEHKdoCgSC/SpnJhmPtHBxXf7/gcirz9EcSO76yp9iN+fUKdo+fw8jQUsPatgPwVuZm970rSK5UMzvMFk5UbMVXyCXtg9psuK8Wxc8t6FhEG7EJ4jhlXMpDtHZaPqjVKEJ0s985zBjIElxShMjdP5nSqyP5pE+1h7yfv/Kv8i0aKp7ZmhZbsIKyUA/CUl5GGzeCmKxa845ywOtm942XuuDAdqY4g0WRBeN0mUoeWnmDkd+5JRrmW8NXUDItFsPyf+epwHMajlFbZIS3PWIS/JnaVMjubzSLVL25Jqsaf+fzWlsY0m+WbCVQbiQJYf8k3AWGWJUcI/0PeyeStEkZKBVVo4+/Q==
  template:
    metadata:
      creationTimestamp: null
      name: my-secret
      namespace: sealed-secrets-demo
```

**Note:** *Your client encrypted the password and placed its result in `my_sealed_secrets.yaml`. You can now share this file with others or even store it in your git repository.*

Now let’s apply our sealed secret to the kubernetes cluster:

```bash
kubectl -n sealed-secrets-demo apply -f my_sealed_secret.yaml
```
```text
sealedsecret.bitnami.com/my-secret created
```

Let’s verify that the controller also created our secret:

```bash
kubectl -n sealed-secrets-demo get secret my-secret -o yaml
```
```yaml
apiVersion: v1
data:
  password: dmVyeSBzZWNyZXQ=
kind: Secret
metadata:
  name: my-secret
  namespace: sealed-secrets-demo
  ownerReferences:
  - apiVersion: bitnami.com/v1alpha1
    controller: true
    kind: SealedSecret
    name: my-secret
    uid: f34eae3d-773b-49a2-a069-daa49942473d
type: Opaque
```

**Note:** *I removed irrelevant fields from the yaml file.*

#### Updating our Secret

Let’s say that we changed our password, and we need to update its corresponding secret in kubernetes.

First, create a new generic secret again. Note that we’re still using a dry run to prevent updating the secret in kubernetes without the sealed secret.

```bash
echo -n “the more secure secret” | kubectl create secret generic my-secret --namespace sealed-secrets-demo --dry-run --from-file=password=/dev/stdin -o yaml > my_secret.yaml
```
```yaml
apiVersion: v1
data:
  password: dGhlIG1vcmUgc2VjdXJlIHNlY3JldA==
kind: Secret
metadata:
  creationTimestamp: null
  name: my-secret
  namespace: sealed-secrets-demo
```

We then follow the same steps as before to create a new sealed secret yaml file.

```bash
kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system --format yaml < my_secret.yaml > my_sealed_secret.yaml
```
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  creationTimestamp: null
  name: my-secret
  namespace: sealed-secrets-demo
spec:
  encryptedData:
    password: AgB6RSzibC7G6V2wzslkKE9OVJ/AQuqF9GoChfrmZFQ/MJN6DDQrKSgOibmTVpbMLSB04IGT7DGISuVNwEXmBJRyLnYI7O6YeVxZrQOhfnLWzu6td3fIlvQNNaiBr57zr8ERLdAFwtgGN1IjYwyLUqhUODuQtFZTPztiBD2euRVqjFY0+rG8fbWHnReJewPbdx7BOZEYRLcDJFnJqniNcsZZiX6Uu2KGLxy1IBwIxdSkjfN5nw+D/9g6bqz10bjT8L002yM6c2+vegkm+oZAWYNKxEs2o/5xB3XhvF07vqOjzxQm1T1mjf3iYkYFUwy9KuxG3olxSLUDz/DJcmnl2n4bKnoVvFEwkhOvDgigSGf0Oa4nj5JtbXIvDIofQFNb79f7lUg0hM4RAwxki+FK5JhhxiquE1uNp5oMtg+FIyV2sTXY2tHEmAsmHU1CZ7d4aAddKrGYgBvJv9pw4CRDZLi2arkSTUgJVTHBYSVvnARWgZpqXh5uUL3cB/JOJKqT2XSDO+oCwpFO90g4lMyOdheVfvQLUO1r2MmD7PvUB1oWm452t3IvJNlAp8NPkHRE4FMT8D8Av1jr7dRs5sDYe965fBHDl+dNUcwVc6zFIDz7xfJnsNGax1hMB3oGhIZHdr+FrmjvjRv0zo3l6Di4nDDhLbYp6kN5/B/wYjOXFILTgl9OHtwITiMmsaXbUUrjie8+uThcxgZQ2cDaUSxofHzE3mKX+sqI
  template:
    metadata:
      creationTimestamp: null
      name: my-secret
      namespace: sealed-secrets-demo
```

Let’s apply this new sealed secret to the cluster:

```bash
kubectl -n sealed-secrets-demo apply -f my_sealed_secret.yaml
```
```text
sealedsecret.bitnami.com/my-secret configured
```

The controller should have also updated our secret, let’s check:

```bash
kubectl -n sealed-secrets-demo get secret my-secret -o yaml
```
```yaml
apiVersion: v1
data:
  password: dGhlIG1vcmUgc2VjdXJlIHNlY3JldA==
kind: Secret
metadata:
  name: my-secret
  namespace: sealed-secrets-demo
  ownerReferences:
  - apiVersion: bitnami.com/v1alpha1
    controller: true
    kind: SealedSecret
    name: my-secret
    uid: f34eae3d-773b-49a2-a069-daa49942473d
type: Opaque
```

**Note:** *I removed irrelevant fields from the yaml file.*

You can see that the controller updated our secret.
