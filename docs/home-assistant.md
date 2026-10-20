# Home Assistant Guide

## After deployment

1. Create a DHCP reservation in the router (the VM's MAC is pinned for that purpose):
   e.g. `10.20.30.42`.
2. Visit that address, create an account, and restore from a backup.
3. If it's a fresh installation: Settings -> System -> Network -> HTTP server ->
   Reverse proxy -> Trust X-Forwarded-For ☑️ + add the Caddy host IP as a trusted
   proxy: `10.20.30.50`
