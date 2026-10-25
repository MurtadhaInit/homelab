# Home Assistant Guide

## Setup after deployment

1. Create a DHCP reservation in the router e.g. `10.20.30.42`.
   - The VM's MAC is pinned for that purpose, so a rebuilt VM comes up on the
     same right address and without manual reconfiguration (e.g. if setting a static
     IP in the Home Assistan Web UI).
2. Visit that address, create an account, and restore from a backup (supplying the
   backup decryption key from a password manager).
3. If it's a fresh installation:
   1. Settings -> System -> Network -> HTTP server ->
      Reverse proxy -> Trust X-Forwarded-For ☑️ + add the Caddy host IP as a trusted
      proxy: `10.20.30.50`
   2. Settings -> System -> Network -> Home Assistant URL -> Internet: set to
      `https://homeassistant.home.murtadha.dev`.
      - These are the addresses HA gives to other devices and services that need
        to fetch something from it (and "Internet" is for clients that might not
        be on the LAN).
      - That domain resolves on the LAN through AdGuard and similarly on the
        tailnet since AdGuard is the tailnet's nameserver.

## Matter over Thread

The Apple TV is the Thread border router, so HA needs no Thread radio of its own.
HA reaches Thread devices over IPv6 routes the Apple TV advertises on the LAN, which
means HA and the Apple TV must share a network segment (mind this when adding VLANs).

Prerequisites:

- An Apple TV model with a Thread radio, set as the home hub in Apple Home:
  Home app -> Home Settings -> Home Hubs & Bridges.
- IPv6 enabled in HAOS (the default): Settings -> System -> Network -> IPv6 ->
  Automatic.

Setup:

1. Settings -> Devices & services -> Add integration -> Matter (accept the
   prompt to install the Matter Server app). The Thread integration is discovered
   separately (from the Apple TV's Thread announcement) and lists the Apple network
   under "Other networks".
2. Import Apple's Thread credentials into HA. In the iOS Companion app: Settings
   -> Companion app -> Debugging -> Thread -> pick the Apple network -> Transfer
   to Home Assistant.
3. In the Thread integration, select "Make preferred network" on that network, so
   anything HA adds to Thread (such as a future HA-owned border router) joins it
   instead of forming a separate mesh.

Adding devices:

- HA only: in the Companion app, Settings -> Devices & services -> Devices -> Add
  device -> Add Matter device, then scan the code. It must be the phone app,
  because pairing uses the phone's Bluetooth.
- Both HA and Apple Home (preferred for Matter devices): add it in Apple Home first,
  then in its settings use "Turn On Pairing Mode" for a one-time code to add it
  to HA. Apple Home then controls it directly, even while HA is down.

## Apple Home

HA owns every device and automation. Apple Home is only the household front end
(Control Center, Watch, CarPlay), so the two never run competing automations.

- Matter devices: share them with Apple Home as above.
- Everything else (e.g. Zigbee): expose a curated subset through the HomeKit Bridge
  integration (under "Apple" when adding the integration).
  - Don't also bridge Matter devices already shared with Apple Home, or they
    show up twice.
