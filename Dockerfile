# MCPHub with a node security overlay: if a newer node patch of the same major
# is out than the one upstream ships, it replaces upstream's binary
# (see node-overlay.sh).
ARG MCPHUB_VERSION
ARG NODE_VERSION
FROM docker.io/library/node:${NODE_VERSION}-trixie-slim AS node

FROM docker.io/samanhappy/mcphub:${MCPHUB_VERSION}
COPY --from=node /usr/local/bin/node /tmp/node-overlay/node
COPY node-overlay.sh /tmp/node-overlay.sh
RUN sh /tmp/node-overlay.sh && rm -rf /tmp/node-overlay /tmp/node-overlay.sh

# Wait for the OIDC IdP before MCPHub starts (see oidc-wait.sh). The upstream entrypoint is
# renamed and the wrapper takes its path, so ENTRYPOINT and CMD stay as upstream defines them.
# mv fails the build if upstream ever moves the file.
COPY --chmod=755 oidc-wait.sh /usr/local/bin/oidc-wait.sh
RUN mv /usr/local/bin/entrypoint.sh /usr/local/bin/entrypoint-upstream.sh \
 && mv /usr/local/bin/oidc-wait.sh /usr/local/bin/entrypoint.sh \
 && command -v curl >/dev/null
