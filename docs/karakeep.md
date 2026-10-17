# Karakeep

The [Karakeep](https://karakeep.app) deployment consists of 3 components:

1. `karakeep-web`: the web app plus background workers (crawling, tagging, embeddings);
  its SQLite DB and assets live on the `karakeep-data-pvc` volume.
2. `karakeep-chrome`: headless Chrome the crawler drives.
3. `karakeep-meilisearch`: search and vector index, derived entirely from the DB.

AI agents interact with Karakeep through its MCP server, run locally by each client
against the public URL and using an API key.

## After a fresh install

1. Sign up to create the admin account; the first account becomes the administrator.
2. Create an API key for the MCP server in *User Settings → API Keys*. The key lives
   in Karakeep's DB, so restoring `karakeep-data-pvc` from a backup keeps it valid;
   only an empty install needs a new one.

## Rebuilding the search index

Needed after wiping Meilisearch or restoring only the DB: *Admin Settings →
Background Jobs → Reindex All Bookmarks* then *Regenerate Embeddings for All
Bookmarks* (embeddings cost a few cents per thousand bookmarks through OpenRouter).

## Upgrading Meilisearch

Meilisearch is pinned to the version in Karakeep's compose file and refuses to
open an index written by another version. Its PVC holds only rebuildable data,
so upgrading means starting from an empty volume:

1. Bump the image tag and push. The new pod fails against the old index; that's
   expected.
2. Scale it down (a PVC can't be deleted while a pod still mounts it) and delete
   the PVC. The Longhorn StorageClass's `Delete` reclaim policy removes the volume
   with it:

   ```nu
   k -n karakeep scale deploy/karakeep-meilisearch --replicas 0
   k -n karakeep delete pvc karakeep-meilisearch-pvc
   ```

3. Let Flux recreate the PVC and restore the replica count from Git:

   ```nu
   flux reconcile kustomization karakeep --with-source
   ```

4. [Rebuild the search index](#rebuilding-the-search-index).
