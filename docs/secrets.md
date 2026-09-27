# Secrets

Secrets are committed to the repo encrypted with [SOPS](https://github.com/getsops/sops)
using a single `age` key pair. The same YAML files are decrypted by Flux (k8s), Ansible, and
OpenTofu. Nix secrets use `agenix` instead (see [decisions](decisions.md)) and they utilise
another `age` key pair.

## How it fits together

- **Private key:** `~/.ssh/keys/sops-age.txt` on the workstation. `mise.toml` exports
  `SOPS_AGE_KEY_FILE` pointing at it, so `sops` works without flags anywhere in the repo.
  The cluster holds a copy as `Secret/sops-age` in `flux-system`, seeded at bootstrap
  (`flux.tf`).
- **Encryption rules:** [`.sops.yaml`](../.sops.yaml) picks the recipient, which YAML
  keys whose values to encrypt, and in which files. Any `*.sops.yaml` gets only its `data`/`stringData` values encrypted (treated as a k8s secret) and the rest of the manifest
  stays readable and diffable.
- **Consumers:**
  - **Flux:** a Flux Kustomization decrypts only if it carries a `decryption:` block, and that
    doesn't cascade to child Flux Kustomizations, only to *standard k8s Kustomizations*. Don't
    place that block on aggregator Flux Kustomizations like `apps` whose path only holds child Flux Kustomization because it would be inert there.
  - **Ansible:** the `community.sops.sops` vars plugin decrypts `host_vars`/`group_vars`
    files on the fly.
  - **OpenTofu:** the `carlpett/sops` provider reads the same Proxmox token files in `host_vars` as
    Ansible.

## Workflow

All commands run from inside the repo (so mise's environment applies and `.sops.yaml` is picked up).

- **Create** a new secret: `sops edit` on a path that doesn't exist yet opens a template in
  `$EDITOR`; replace it with the `Secret` manifest and save. It's encrypted on save, so plaintext
  never touches the disk.

  ```nu
  sops edit k8s/apps/<app>/app/secret.sops.yaml
  ```

  Generate random values with `openssl rand -base64 36` and use `stringData` for
  plaintext (rather than base64 encoded) values.
- **Encrypt** a file already written in plaintext (⚠️ never commit before this):

  ```nu
  sops encrypt --in-place k8s/apps/<app>/app/secret.sops.yaml
  ```

- **Edit** (decrypts into `$EDITOR`, re-encrypts on save): `sops edit <file>`.
- **View:** `sops decrypt <file>`.
- **Verify it's encrypted before committing:** `sops filestatus <file>` →
  `{"encrypted":true}`.

## Rotation

- **Data key** (re-encrypts a file's values under a fresh key, same recipient):
  `sops rotate --in-place <file>`.
- **Recipients** (new or additional age key): update `.sops.yaml`, then re-wrap every file:

  ```nu
  glob **/*.sops.yaml | each { |f| sops updatekeys --yes $f }
  ```

  If the old key is retired, also replace `Secret/sops-age` in the cluster, or Flux can no
  longer decrypt.
