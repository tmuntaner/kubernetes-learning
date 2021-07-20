# IAM Roles in EKS Deployments

Sometimes you want to give your kubernetes pods access to the AWS api. Without service roles, you would need to give your containers the environmental variables like `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. This can quickly become a security issue, as well as a nightmare to deploy new keys.

The use of the service account allows your pods to avoid setting environmental variables, instead allowing your containers to assume wanted roles, all by only specifying a service role.

**Notes:**

* You can view the AWS documentation at https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html.

## Prerequisites

* An EKS cluster.
* Before you continue, the cluster administrator should have already set up an IAM OIDC provider for the cluster. If not, use the [AWS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html) to set it up. You'll want to record the ARN of the provider for the variable `eks_federated_web_identity`, it should look like `arn:aws:iam::xxxxxxx:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/XXXXXXXXXXXXX`.

## Set up the Role with Terraform

We want to create an AWS role for our pod assume. Please use the following terraform configuration to build your own role.

```terraform
// The ARN for the IAM OIDC provider. See the above prerequisite.
variable "eks_federated_web_identity" {}

// The kubernetes namespace which you want to allow the use of your policy.
variable "namespace" {}

// The name of the service account, if not set, it allows all service accounts in the kubernetes namespace.
variable "service_account_name" {
  default = '*'
}

provider "aws" {
  region  = "eu-west-1"
}

/*
 * This is the role you want to give to your pod.
 */
resource "aws_iam_policy" "main" {
  name        = "example-service-role-policy"
  path        = "/"
  description = "service role permissions for eks"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:*"
        ],
        Resource = [
          "*"
        ]
      },
    ]
  })
}

/**
 * Create the IAM role
 */
resource "aws_iam_role" "main" {
  name = "example-eks-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = var.eks_federated_web_identity
        }
        Condition = {
          StringEquals = {
            "oidc.eks.eu-west-1.amazonaws.com/id/E74856BD818DB239C07AA1D72F74E83B:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
            "oidc.eks.eu-west-1.amazonaws.com/id/E74856BD818DB239C07AA1D72F74E83B:aud" = "sts.amazonaws.com"
          }
        }
      }
    ],
  })
}

/*
 * Attach the policy to the IAM role
 */
resource "aws_iam_role_policy_attachment" "main" {
  policy_arn = aws_iam_policy.main.arn
  role = aws_iam_role.main.name
}

output "role_arn" {
  value = aws_iam_role.main.arn
}
```

After the role is created, you'll want to take note of the output of the `role_arn` for your service account.

## Kubernetes Service Account

After you created your role above with terraform, you'll need to create a kubernetes service account. Below is an example yaml declaration, but you'll need to replace `ROLE_ARN` with the ARN found above.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: SERVICE_ACCOUNT_NAME
  annotations:
    eks.amazonaws.com/role-arn: ROLE_ARN
```

## Use the Service Account in your Pod Configuration

The use of your service account depends on whether your container uses `root` as its user. If it doesn't use `root` (recommended), you'll want to specify the `GROUP_ID` to prevent permission issues.

### With a container not using the root user (recommended)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  labels:
    app: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      securityContext:
        fsGroup: GROUP_ID
      serviceAccountName: SERVICE_ACCOUNT_NAME
      containers:
      - name: my-container
        image: my-container:1
        ports:
        - containerPort: 8080
```

### With a container using the user root

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  labels:
    app: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: SERVICE_ACCOUNT_NAME
      containers:
      - name: my-container
        image: my-container:1
        ports:
        - containerPort: 8080
```
