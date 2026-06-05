# Grafana MCP server

The [Grafana MCP server](https://grafana.com/docs/grafana/latest/developer-resources/mcp/)
is configured in `.mcp.json` and authenticates to Grafana with a **service-account
token** which lives in the OS keyring; `mise.toml` reads it into
`GRAFANA_SERVICE_ACCOUNT_TOKEN` environment variable at runtime via a
cross-platform `exec()` lookup (macOS `security`, falling back to Linux `secret-tool`).

## Per-cluster setup

1. **Create the token**: in Grafana: *Administration → Users and access →
   Service accounts* → create one ('Viewer' if you want read-only MCP use) →
   *Add service account token* → copy it.
2. **Store it in the workstation's OS keyring**:
   1. `just grafana-mcp-token`.
   2. then paste the token when prompted (it is read silently, so it never lands
      in shell history).
   - On a fresh machine this works on macOS (login keychain) and
     on a Linux desktop with a Secret Service daemon (GNOME Keyring, KWallet, …).
3. **Point at the right Grafana**: if this cluster's Grafana URL differs, edit
   `GRAFANA_URL` in `.mcp.json`.
4. **Fresh clone only:** run `mise trust` so mise will execute the keyring
   lookup. Then reload the Grafana MCP server in the AI assistant.
   - If the keyring entry is missing, the lookup resolves to an empty string and
     mise does not error.

## Rotating / removing the token

- **Rotate / switch clusters:** generate a new token and re-run
  `just grafana-mcp-token` (it updates the entry in place).
- **Remove (macOS):** `security delete-generic-password -s grafana-mcp-token`
- **Remove (Linux):** `secret-tool clear service grafana-mcp-token`
