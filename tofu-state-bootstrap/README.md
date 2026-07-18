# tofu-state-bootstrap/ — run ONCE per AWS account

Creates the account's OpenTofu **state bucket** — named `rds-tofu-state-<random>`
(AWS's suffix makes it globally unique; no account number needed) with
versioning, encryption, and public-access-block — and writes the generated name
to the SSM parameter **`/rds/tofu/state-bucket`**, the fixed per-account path
that lets `make init` discover the bucket instead of anyone memorizing it.

```bash
make state-bootstrap        # from the repo root, with the TARGET account's creds
```

One bucket per account, ever: it holds the state of *every* module in this
repo (keys are namespaced per module, e.g. `tofu/terraform.tfstate`). Not for
laptops — this runs only when setting up an AWS account.

This root's own state is local and disposable. If every note is lost, the
bucket is rediscoverable from the account itself:

```bash
aws ssm get-parameter --name /rds/tofu/state-bucket --query Parameter.Value --output text
aws s3 ls | grep rds-tofu-state      # fallback
```

Adopting remote state in a module afterwards: [`../docs/remote-state.md`](../docs/remote-state.md).
