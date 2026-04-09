# To Do

1. Disable the listening of services of 0.0.0.0 and revert to localhost (don't open ports in the firewall) since Caddy handles the reverse proxy into those services as `localhost:<port>`.
2. Consider setting up encryption in Adguard Home to both allow clients to use DoH/DoT with the DNS server and crucially to identify clients uniquely in Adguard Home.
3. Use an external secrets provider like Hashicorop Vault along with ephemeral resources in the Talos provider (also update to 0.11 when it's out of beta).
4. Adopt a better secrets management solution and remove the .env file along with its mise entry and .gitignore entry.

## Notes

- Get the hash for the new release version with `nurl`, e.g.:
  - `nix run github:nix-community/nurl -- <https://github.com/caddy-dns/cloudflare> v0.2.4`
  - Or: `nix run nixpkgs#nurl -- <https://github.com/caddy-dns/cloudflare> v0.2.4`
