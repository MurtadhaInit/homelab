# Redundant DNS with AdGuard Home and Keepalived

High-availability DNS for the home network using two AdGuard Home instances
behind a keepalived virtual IP, with a public resolver as a last-resort fallback.

## Rationale

AdGuard Home currently runs inside the `nixos-ct` LXC container on a single
Proxmox host. Any disruption — NixOS rebuild, container restart, Proxmox
upgrade, or hardware failure — leaves all clients unable to resolve DNS.

This plan introduces a second AdGuard Home instance on dedicated hardware
(separate physical machine) with keepalived managing a floating virtual IP (VIP).
The VIP is advertised as the primary DNS via DHCP. If the master goes down, the
backup takes over the VIP within 1-3 seconds — transparent to clients. A public
resolver (e.g. `1.1.1.1`) is set as the secondary DNS in DHCP as a last-resort
fallback if both instances are unreachable.

### Why keepalived over simply listing two DNS IPs in DHCP?

When DHCP hands clients two DNS addresses, failover depends on each OS's
resolver behaviour. Most clients only try the secondary after the primary
**times out** (1-5 seconds depending on OS), causing a noticeable stall on every
query during the outage. With a keepalived VIP, failover happens at the network
layer in 1-3 seconds — clients always talk to the same IP and never experience
per-query timeouts.

## Hardware

**ZimaBoard 2** (Intel N150, 8/16GB LPDDR5x, 32/64GB eMMC, dual SATA III,
dual 2.5GbE, fanless aluminium enclosure). Runs Proxmox as the hypervisor with
the NixOS DNS config deployed as an LXC container — mirroring the existing
`nixos-ct` setup on the primary node.

The ZimaBoard 2's dual SATA ports allow attaching a spare 2.5" Samsung SSD
(250GB) for the Proxmox root filesystem and LXC storage, avoiding eMMC wear
from constant DNS query logging. The eMMC can serve as the boot device or be
left unused.

## Current State

```
nixos-ct (Proxmox LXC on primary node) — 10.20.30.50
├── AdGuard Home (DNS + ad-blocking)
├── Caddy, Grafana, Prometheus, Jellyfin, ...
└── All other homelab services

UniFi DHCP → DNS: 10.20.30.50
```

## Target State

```
UniFi DHCP DNS settings:
  Primary:   10.20.30.53  (keepalived VIP — floating)
  Secondary: 1.1.1.1      (public fallback)

nixos-ct (Proxmox LXC on primary node) — 10.20.30.50 (unchanged)
├── AdGuard Home
├── Caddy, Grafana, Prometheus, Jellyfin, ... (unchanged)
├── keepalived (MASTER, priority 150, manages VIP .53)
└── DNS rewrites: *.home.lan → 10.20.30.50 (this node — where Caddy runs)

nixos-dns (Proxmox LXC on ZimaBoard 2) — 10.20.30.52
├── AdGuard Home (same config)
├── keepalived (BACKUP, priority 100, takes VIP on failover)
└── DNS rewrites: *.home.lan → 10.20.30.50 (still points to nixos-ct)
```

### How DNS queries flow

```
Client → "what's grafana.home.lan?" → VIP (.53, port 53)
                                        │
                            whichever AdGuard instance holds the VIP
                                        │
                                   answer: 10.20.30.50
                                        │
Client → HTTPS → 10.20.30.50:443 → Caddy → Grafana (localhost)
```

The VIP is only the address clients use to **send DNS queries**. The DNS rewrite
answers always point to `10.20.30.50` (nixos-ct) because that's where Caddy and
all reverse-proxied services run. During failover, the backup node answers DNS
queries identically — it still tells clients to connect to `.50` for HTTP.
If `nixos-ct` itself is down, those services are unavailable regardless, but
DNS resolution for the internet (ad-blocking, upstream forwarding) continues
working via the backup.

## IP Addressing

| Address       | Role                                   |
|---------------|----------------------------------------|
| 10.20.30.50   | nixos-ct real IP (unchanged — Caddy, services, AdGuard Home) |
| 10.20.30.52   | nixos-dns real IP (ZimaBoard 2 — AdGuard Home backup) |
| 10.20.30.53   | Virtual IP (VIP) — managed by keepalived, floats between .50 and .52 |
| 1.1.1.1       | Public fallback DNS in DHCP secondary slot |

No IP renumbering is required. The VIP `.53` is a new address that neither node
owns statically — keepalived assigns it dynamically to the current master.

## Implementation Steps

### Phase 1: Keepalived NixOS Module

Create `Nix/modules/keepalived.nix` — a reusable homelab module wrapping
`services.keepalived` with options for the VIP, priority, and health checks.

```nix
# Sketch — not final
options.homelab.keepalived = {
  enable = lib.mkEnableOption "keepalived VRRP for DNS failover";
  virtualIp = lib.mkOption {
    type = lib.types.str;
    default = "10.20.30.53";
    description = "The floating virtual IP address";
  };
  interface = lib.mkOption {
    type = lib.types.str;
    default = "eth0";
    description = "Network interface to attach the VIP to";
  };
  priority = lib.mkOption {
    type = lib.types.int;
    description = "VRRP priority — higher value wins master election (e.g. 150 for master, 100 for backup)";
  };
  routerId = lib.mkOption {
    type = lib.types.int;
    default = 53;
    description = "VRRP router ID — must be the same on both nodes";
  };
};
```

The module should:

- Enable and configure `services.keepalived` with a VRRP instance
- Include a health check script that verifies AdGuard Home is responding on
  port 53 (e.g. `dig @127.0.0.1 localhost +time=2`). If the check fails,
  keepalived should reduce its effective priority so the backup takes over
  even if the node itself is still reachable
- Open the necessary firewall ports (VRRP uses protocol 112)
- Send gratuitous ARP on failover (keepalived does this by default)

### Phase 2: New NixOS Host Configuration

Create `Nix/hosts/nixos-dns/default.nix` for the new Proxmox LXC on the
ZimaBoard 2.

This host will:

- Run as a Proxmox LXC container (same as `nixos-ct`)
- Import `proxmox-lxc.nix`, `modules/base.nix`, `modules/adguardhome.nix`,
  and `modules/keepalived.nix`
- Use the same AdGuard Home configuration as `nixos-ct` (same filters,
  same DNS rewrites, same upstream resolvers)
- Set keepalived priority to 100 (BACKUP)
- Proxmox manages networking with static IP `.52`

```nix
# Sketch — Nix/hosts/nixos-dns/default.nix
{ modulesPath, config, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/base.nix
    ../../modules/adguardhome.nix
    ../../modules/keepalived.nix
  ];

  system.stateVersion = "25.11";

  proxmoxLXC = {
    manageNetwork = false;
    manageHostName = false;
    privileged = true;    # may need to be true for keepalived VIP management
  };

  systemd.network.wait-online.enable = false;
  services.fstrim.enable = false;

  homelab.adguardhome = {
    enable = true;
    publicDomain = "home.murtadha.dev";
    # lanAddress stays 10.20.30.50 — Caddy runs on nixos-ct, not here
  };

  homelab.keepalived = {
    enable = true;
    priority = 100;  # BACKUP
  };
}
```

ZimaBoard 2 storage considerations:

- Install Proxmox on the spare Samsung 2.5" SSD (250GB) via SATA — this avoids
  eMMC wear from the LXC container's writes (query logs, nix store, etc.)
- The eMMC (32/64GB) can serve as the EFI boot device or be left unused
- The second SATA port is available for future expansion

### Phase 3: Flake Changes

Update `Nix/flake.nix`:

- Add `nixos-dns` to `nixosConfigurations` (x86_64-linux, same as `nixos-ct`)
- Add `nixos-dns` to `deploy.nodes` for deploy-rs
- No new flake inputs needed — ZimaBoard 2 is standard x86_64

```nix
# Sketch
nixosConfigurations.nixos-dns = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    ./hosts/nixos-dns
    agenix.nixosModules.default
  ];
};

deploy.nodes.nixos-dns = {
  hostname = "nixos-dns";
  sshUser = "root";
  profiles.system = {
    user = "root";
    path = deploy-rs.lib.x86_64-linux.activate.nixos
      self.nixosConfigurations.nixos-dns;
  };
};
```

### Phase 4: Update nixos-ct

Modify `Nix/hosts/nixos-ct/default.nix`:

- Import `modules/keepalived.nix`
- Set keepalived priority to 150 (MASTER)
- No IP change needed — `nixos-ct` stays at `.50`
- `homelab.adguardhome.lanAddress` stays `10.20.30.50` (default) — Caddy and
  all services run here, so DNS rewrites must point clients to this IP

### Phase 5: AdGuard Home Config Sync Strategy

Both nodes need identical AdGuard Home configurations (filters, DNS rewrites,
upstream resolvers, blocklists). Since the NixOS module declares settings
declaratively in Nix, this is handled automatically — both hosts import the
same `modules/adguardhome.nix` module with the same options.

**What stays in sync via Nix (declarative):**

- Upstream DNS servers
- Filter lists and URLs
- DNS rewrites (`*.home.lan → 10.20.30.50`, i.e. nixos-ct where Caddy runs)
- DNSSEC, ratelimit, rDNS settings

**What does NOT sync (mutable state):**

- `mutableSettings = true` means runtime changes in the AdGuard web UI
  (e.g. adding a custom filter rule) only apply to that node
- Query logs and statistics are per-node

**Recommendation:** Set `mutableSettings = false` on the backup node
(`nixos-dns`) so it is purely declarative. Keep `mutableSettings = true` on
the primary (`nixos-ct`) for convenience, but document that any permanent
changes should be committed to the Nix module.

### Phase 6: eMMC Write Mitigation

The ZimaBoard 2 has dual SATA III ports and 32/64GB eMMC. The primary
mitigation is to install Proxmox on the spare Samsung 2.5" SSD so the LXC
container's storage lives on the SSD, not eMMC. This largely eliminates the
concern.

If for any reason the eMMC ends up hosting the LXC:

- Disable query logging on the backup node or set a short retention:
  ```nix
  # On nixos-dns only — override the default 30-day retention
  services.adguardhome.settings.querylog = {
    interval = "24h";
    # Or disable entirely:
    # enabled = false;
  };
  services.adguardhome.settings.statistics.interval = "24h";
  ```
- Alternatively, point AdGuard Home's data directory to tmpfs:
  ```nix
  boot.tmp.useTmpfs = true;
  ```

### Phase 7: UniFi DHCP Configuration

After both nodes are running and keepalived is confirmed working:

1. In UniFi Network → Settings → Networks → (your VLAN/network):
   - Primary DNS: `10.20.30.53` (the VIP)
   - Secondary DNS: `1.1.1.1` (public fallback)
2. Clients will pick up the new DNS settings on their next DHCP renewal
   (or force with `ipconfig /renew`, `sudo dhclient -r && sudo dhclient`, etc.)

### Phase 8: Testing and Validation

1. **VIP is active on master:**
   ```nu
   # From any client:
   dig @10.20.30.53 example.com  # should resolve
   # On nixos-ct:
   ip addr show eth0  # should show both .50 and .53
   ```

2. **Failover works:**
   ```nu
   # Stop AdGuard Home on the master:
   systemctl stop adguardhome  # on nixos-ct
   # Within 1-3 seconds, the VIP should move to nixos-dns
   # From any client:
   dig @10.20.30.53 example.com  # should still resolve
   # On nixos-dns:
   ip addr show eth0  # should now show .52 and .53
   ```

3. **Failback works:**
   ```nu
   # Restart AdGuard Home on the master:
   systemctl start adguardhome  # on nixos-ct
   # VIP should return to nixos-ct (higher priority)
   ```

4. **Public fallback works:**
   ```nu
   # Stop keepalived on BOTH nodes (simulating total infra failure):
   # From a client:
   # DNS queries will timeout on .53 (1-5s) then fall back to 1.1.1.1
   # Internet should still work, just without ad-blocking
   ```

5. **Ad-blocking is consistent:**
   - Test a known blocked domain against the VIP from a client
   - Verify it's blocked regardless of which node is master

6. **DNS rewrites work:**
   - `dig grafana.home.lan @10.20.30.53` should return `10.20.30.50`
     (nixos-ct, where Caddy runs)
   - `dig grafana.home.murtadha.dev @10.20.30.53` should also return
     `10.20.30.50`

## Firewall Rules

Both nodes need:

| Port/Protocol | Purpose |
|---------------|---------|
| UDP/53        | DNS queries |
| TCP/53        | DNS queries (TCP fallback) |
| TCP/3080      | AdGuard Home web UI |
| Protocol 112  | VRRP (keepalived heartbeats) |

The keepalived module should open protocol 112. The AdGuard Home module already
opens 53 and 3080.

## Rollback Plan

If something goes wrong during migration:

1. **Before starting**: Take a Proxmox snapshot of `nixos-ct`
2. **If VIP doesn't work**: Revert UniFi DHCP to point directly at
   `10.20.30.50` (nixos-ct's real IP, unchanged from today)
3. **If keepalived is unstable**: Disable the keepalived module on both nodes,
   revert UniFi DHCP to `.50`, and you're back to the current single-server
   setup with zero changes to existing infrastructure

Since `nixos-ct` keeps its `.50` address throughout, the rollback is trivial —
just remove the VIP from DHCP and disable keepalived.

## Decisions Made

- [x] **VIP address**: `10.20.30.53` — nixos-ct stays at `.50`, no renumbering
- [x] **Hardware**: ZimaBoard 2 (Intel N150, x86_64) — no ARM flake inputs needed
- [x] **Second node runs Proxmox**: NixOS as LXC container, same as nixos-ct
- [x] **DNS rewrites stay at `.50`**: Caddy + services run on nixos-ct only.
      Both AdGuard instances return `.50` for `*.home.lan` / `*.home.murtadha.dev`.
      The VIP is only the DNS server address, not the rewrite target
- [x] **eMMC mitigation**: Install Proxmox on spare Samsung 2.5" SSD via SATA

## Open Questions

- [ ] **VRRP authentication**: Should the VRRP instance use a shared secret?
      Recommended if the VLAN has untrusted devices
- [ ] **Monitoring**: Add a Prometheus alert for keepalived state changes
      (master → backup transitions)
- [ ] **Keepalived in LXC**: Keepalived needs to manage virtual IPs and send
      gratuitous ARPs, which may require the LXC container to be privileged
      and/or have specific capabilities (NET_ADMIN, NET_RAW). Test and document
      any Proxmox LXC config needed
- [ ] **AdGuard Home web UI access**: With the VIP, the AdGuard UI at
      `.53:3080` will point to whichever node is master. Consider whether both
      UIs should be accessible independently via `.50:3080` and `.52:3080` for
      management purposes
