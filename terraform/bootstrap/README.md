# Bootstrap

Creates the S3 bucket that holds Terraform state for every environment. Run once,
before anything else, and then largely forget about it.

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

This root keeps its state **locally**, in `terraform.tfstate` next to these files, and
that file is committed. That is normally bad practice, but the alternative is a bucket
that stores the state describing itself, which cannot be created in one step. The
tradeoff is deliberate: this state contains no secrets, only a bucket name.

The bucket has `prevent_destroy` set. Deleting it orphans every resource Terraform
manages across all environments, so removing that line has to be a conscious decision.
