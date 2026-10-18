# keepass-retrieve-secret

Retrieves a single field from a KeePass entry via `keepassxc-cli`. Used
throughout [terragrunt/](../../../../terragrunt/README.md) module inputs
(`run_cmd(..., "keepass-retrieve-secret", ...)`) to pull secrets at
Terragrunt parse time.

## Usage

```sh
keepass-retrieve-secret --secret-path <path> [--key-name <field>]
```

- `--secret-path` (required) — the KeePass entry path, e.g.
  `Server/Your_Spotify`.
- `--key-name` (optional, default `Password`) — the field to read, e.g.
  `Username`.

## Example

```sh
keepass-retrieve-secret --secret-path "Server/Your_Spotify" --key-name "Username"
keepass-retrieve-secret --secret-path "Server/Your_Spotify"   # defaults to the Password field
```

## What it does

- If `$KEEPASS_PASSWORD` isn't already set, decrypts it from
  `$ATILS_CONFIG_DIRECTORY/keepass-password` with `age` (using
  `~/.ssh/id_ed25519`) and `eval`s the result into the shell.
- Runs `keepassxc-cli show -q -s -k "$KEEPASS_KEY_FILE_PATH" -a "$KEY_NAME" "$KEEPASS_DB_PATH" "$SECRET_PATH"`,
  piping `$KEEPASS_PASSWORD` in as the database password, and prints the
  field value to stdout.

## Prerequisites

- `keepassxc-cli` and `age` on `PATH`.
- `ATILS_CONFIG_DIRECTORY/keepass-password` present and decryptable with
  `~/.ssh/id_ed25519` (unless `KEEPASS_PASSWORD` is already set in the
  environment).
- `KEEPASS_KEY_FILE_PATH` and `KEEPASS_DB_PATH` set, pointing at the
  KeePass key file and database.

## Caveats

- `--secret-path` is required; the script errors out if it's missing.
- An unrecognized flag is rejected as an unknown argument.
