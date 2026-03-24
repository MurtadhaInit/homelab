# To Do

1. Disable the listening of services of 0.0.0.0 and revert to localhost (don't open ports in the firewall) since Caddy handles the reverse proxy into those services as `localhost:<port>`.
2. Consider setting up encryption in Adguard Home to both allow clients to use DoH/DoT with the DNS server and crucially to identify clients uniquely in Adguard Home.

## Notes

- Get the hash for the new release version with `nurl`, e.g.:
  - `nix run github:nix-community/nurl -- <https://github.com/caddy-dns/cloudflare> v0.2.4`
  - Or: `nix run nixpkgs#nurl -- <https://github.com/caddy-dns/cloudflare> v0.2.4`
