# To Do

1. Disable the listening of services of 0.0.0.0 and revert to localhost (don't open ports in the firewall) since Caddy handles the reverse proxy into those services as `localhost:<port>`.
2. Consider setting up encryption in Adguard Home to both allow clients to use DoH/DoT with the DNS server and crucially to identify clients uniquely in Adguard Home.
3. Use an external secrets provider like Hashicorop Vault along with ephemeral resources in the Talos provider (also update to 0.11 when it's out of beta).
4. Adopt a better secrets management solution and remove the .env file along with its mise entry and .gitignore entry.
5. Change the namespace used for Cilium when deployed as an embedded Helm chart and change the namespace used for Flux source and kustomization CRDs to be in some other namespace (maybe).
6. Think about the scenario where the DNS setup might not be effective if the device is tethered to an iPhone for Wifi (over-data). In that case it won't be able to resolve addresses as the DNS service will be offline (no internet).
7. Think about deploying another DNS instance on a VPS for constant uptime. This should ideally be virtualised as well as other services are also worth running on a VPS for redundancy and uptime.
8. Separate what's deployed on the NixOS LXC container by concern and create multiple containers (e.g. one for media, one for observability, one for network/infra) and possibly share teh Nix store between them as a bind-mount to save space.

## Notes

- Get the hash for the new release version with `nurl`, e.g.:
  - `nix run github:nix-community/nurl -- <https://github.com/caddy-dns/cloudflare> v0.2.4`
  - Or: `nix run nixpkgs#nurl -- <https://github.com/caddy-dns/cloudflare> v0.2.4`
