# Remote state — one shared truth per account, discovered not memorized

Local `terraform.tfstate` means the last laptop to `apply` owns the truth: no
locking against concurrent applies, divergence between operators, and a dead
disk loses the state. Remote state fixes all three: **one S3 bucket per AWS
account** holds the state of every module in this repo, versioned (roll back a
bad state), encrypted at rest, and locked during applies (native S3 lockfile —
no DynamoDB needed, requires tofu >= 1.10).

**The bucket belongs to the infrastructure, not the person.** Everyone who
operates an account shares that account's bucket through their own
credentials. Personal sandbox accounts get their own buckets because they are
their own infrastructure.

## Nothing is hardcoded — the account answers

S3 bucket names are globally unique, so the same literal name cannot exist in
every account. Instead the repo commits only a *convention*:

- Buckets are born from prefix `rds-tofu-state-` (AWS appends a random,
  globally-unique suffix — no account numbers in names).
- The generated name is written to the SSM parameter
  **`/rds/tofu/state-bucket`** — a fixed path, identical in every account.
- `make init` *discovers* the bucket (SSM parameter first, prefix listing as
  fallback) from whatever account your credentials point at, and injects it
  via `-backend-config`. Backend blocks stay empty in git.

## The three steps

**1 — Once per account** (org account for prod; your own for a sandbox):

```bash
make state-bootstrap        # creates bucket + SSM pointer, prints the name
```

**2 — Once per module** (explicit adoption, per the repo's `.example` convention):

```bash
cp tofu/backend.tf.example tofu/backend.tf     # backend.tf is gitignored
```

**3 — Once per machine:**

```bash
make init MODULE=tofu       # discovers the bucket, runs tofu init
# first time: tofu asks to migrate the existing local state up — answer yes
```

After that, plain `tofu plan` / `apply` read and write the shared state.
`make init` fails fast and side-effect-free at every missing precondition: no
MODULE named, module not adopted, no credentials, no bucket bootstrapped.

## Recovery ("what was the bucket called?")

The account is the source of truth for its own name — nothing to lose:

```bash
aws ssm get-parameter --name /rds/tofu/state-bucket --query Parameter.Value --output text
aws s3 ls | grep rds-tofu-state
```

## Read-only operators (e.g. the `rds-LLM` role)

After a module migrates, read-only planning needs **s3 read on the state
bucket** (`GetObject` on `<bucket>/<module>/*` + `ListBucket`), and should run
`tofu plan -lock=false` — taking the lock writes a lockfile object, which a
read-only role can't. Grant this when adopting in the org account or read-only
plans stop working.

## Deliberately deferred

- **Client-side state encryption** (OpenTofu-native, passphrase-based): real
  win — the bucket's copy becomes ciphertext — but a lost passphrase means
  lost state, so it deserves its own careful step (passphrase held in SSM
  SecureString + 1Password break-glass). Not wired yet.
- **CI-only applies** (GitHub Actions + OIDC, laptops only ever plan): the
  mature endpoint; arrives with the deploy-workflow migration.
