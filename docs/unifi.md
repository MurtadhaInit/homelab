# UniFi Setup

## Programmatic local access to the Unifi console (e.g. the UDR)

### Creating a local user (for Home Assistant & UnPoller)

This is used for both the Home Assistant integration and for collecting metrics via UnPoller.

1. Login to the UniFi OS console -> People (bottom of the left ribbon) -> Add New Person -> ☑️ Admin -> add the details (e.g. just the first name) -> set a username (like `automation`) and a password -> ☑️ Local Account Only -> set the roles (permissions): Network to Full Management and OS Settings to None -> Save.
2. Use the login credentials (username & password) of this newly created user wherever required to grant access.

### Generating an API key (for the UniFi MCP server)

The [UniFi MCP server](https://github.com/enuno/unifi-mcp-server) uses an API key rather than login credentials, but as of now (23/11/2026) it's not possible to set permissions on a locally created API key. Instead the key inherits the permissions of the user creating it. For this reason, if we want a read-only API key...

1. First create a local user like above but except give it full access. This is needed because a view-only user can't generate API keys (the Integrations section will be hidden).
2. Then logout and log back in but this time using the credentials of this newly created user.
3. Integrations (bottom left ribbon) -> Create New API Key (and give it a name, like `mcp`).
4. Use that generated key to grant the MCP server access: `just mcp-secret unifi` -> paste the key.
5. ⚠️Important⚠️ logout then log back in but this time as the main admin -> People -> select the newly created admin user -> downgrade permissions back to View Only (e.g. for both Network and Control Plane or use 'custom' and set Control Plane to None).
