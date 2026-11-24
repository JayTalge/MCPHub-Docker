# MCPHub-Docker

The official [MCPHub](https://github.com/samanhappy/mcphub) image with a node security overlay. When a newer node patch of the same major is out than the one MCPHub ships, the build replaces MCPHub's node binary with it. Once upstream catches up, the overlay does nothing. This repo contains only the Dockerfile, the scripts and a build workflow. The upstream code is not forked.

| Image | Tags |
|---|---|
| `ghcr.io/jaytalge/mcphub` | `<version>` (e.g. `1.2.5`), `<minor>` (e.g. `1.2`), `latest` |

Only the slim upstream image is mirrored (not `-full`, which adds browsers and a Docker daemon).

## Build

- Every day at 02:37 UTC the workflow takes the newest patch of the **last 2 minor lines** up to MCPHub's `latest` (`edge` and `-full` tags are skipped).
- A version is rebuilt when it is new or when a newer node patch is out (label `de.jason-talge.build-key` = `<version>/node-<node>`).
- Before pushing, the image is smoke-tested in database mode with pgvector: `/health`, version from `/app/package.json`, node not older than the overlay, admin login against Postgres, OAuth server metadata, `/mcp` answers 401 with `resource_metadata`, no fatal errors in the log.
- To build manually, use Actions → "Build image from upstream release" → Run workflow. You can enter a specific version and choose "force". A manual version build also moves its `<minor>` tag.
- `/etc/node-overlay` in the image records what the overlay did.

## Usage

```yaml
services:
  mcphub:
    image: ghcr.io/jaytalge/mcphub:1.2   # patch updates via Watchtower, minor bumps by hand
    volumes:
      - ./data:/app/data
```

### OIDC wait

MCPHub registers its OIDC provider only once at start and skips it permanently (`Provider "oidc": … Provider skipped`) if the IdP does not answer the discovery request then, e.g. when both come up together after a reboot. The image therefore waits for `BETTER_AUTH_OIDC_DISCOVERY_URL` (or `OIDC_DISCOVERY_URL`) before starting MCPHub. `OIDC_WAIT_SECONDS` sets the maximum wait (default 300, `0` disables). After the timeout MCPHub starts anyway, so the local admin fallback keeps working with a dead IdP. A discovery URL that exists only in `mcp_settings.json` is not watched. The upstream entrypoint stays in the image as `/usr/local/bin/entrypoint-upstream.sh`.

For automatic patch updates, pin the minor tag and let Watchtower update the container. Switch to a new minor line by hand. Database mode needs a persistent `JWT_SECRET`, `BETTER_AUTH_SECRET` and credential key (`MCPHUB_CREDENTIAL_ENCRYPTION_KEY` or the key file next to the settings path); see the upstream docs.
