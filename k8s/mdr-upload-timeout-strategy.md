# MDR large-upload timeout strategy for ACC and production

## Summary

MDR must support individual uploads up to **150GB** in production. A fixed
request-body deadline is unsuitable for this: a healthy upload may take hours,
depending on the user's connection and storage throughput.

The recommended strategy is to stream uploads through an nginx proxy using
**inactivity timeouts**, rather than imposing a short maximum upload duration.
Traefik's outer request-body deadline must also be removed on the upload traffic
path. Adding nginx alone does not bypass a timeout enforced by Traefik.

This document describes a proposal, not a deployed ACC/production configuration.

## What happened in TST

The request path was:

```text
Browser → Traefik Gateway API → MDR/Gunicorn → iRODS → ires-hnas-um
```

On 17 November 2026:

- Small uploads succeeded, but approximately 1.1GB files failed.
- The UI reported a timeout; MDR logged an `AttributeError` when the incomplete
  multipart request left `request.FILES.get("upload")` empty.
- iRODS retained incomplete `.part` objects of approximately 150–160MB.
- Traefik 3.7.15 had no explicit request-body read-timeout override. Its default
  `entryPoints.<name>.transport.respondingTimeouts.readTimeout` is **60 seconds**.
  This limits the time to read the **entire request, including its body**, not
  merely the time between received chunks.

We raised this setting to `3600s` for TST's HTTP and HTTPS entrypoints. A retry
then completed successfully at 14:10:33:

- MDR returned HTTP 200.
- The audit trail recorded one successful upload and zero failures.
- iRODS finalized `upload_test.bin` on `stagingResc01` (ires-hnas-um), with size
  **1,073,741,824 bytes (1GiB)**.

This strongly supports the 60-second read deadline as the cause of the test
failure. It does not establish support for 150GB uploads.

### Temporary configuration

The TST HelmChartConfig now uses a one-hour read timeout. The corresponding
Ansible source was updated at:

```text
/home/rjuhasz/repos/dh-ansible/roles/dh.kubernetes/files/traefik-values.yaml
```

```yaml
ports:
  web:
    transport:
      respondingTimeouts:
        readTimeout: 3600s
  websecure:
    transport:
      respondingTimeouts:
        readTimeout: 3600s
```

This is a workaround, not the proposed production policy. At 2.6MB/s, 150GB
takes roughly **16 hours**. Even a one-hour deadline can terminate a healthy
upload. The setting also affects all hosts sharing those entrypoints.

## Timeout types must remain separate

| Timeout | Purpose | Upload policy |
| --- | --- | --- |
| Whole-request read deadline | Limits total time to receive headers and body | Disable on the upload entrypoint; do not size it from one test file |
| Client-body inactivity | Detects a client that stops sending data | Use nginx `client_body_timeout`; tune and test |
| Upstream connect | Detects an unavailable MDR backend | Keep short and finite |
| Upstream write inactivity | Detects stalled forwarding to MDR | Use finite nginx `proxy_send_timeout`; allow expected iRODS backpressure |
| Upstream read inactivity | Detects a backend that stops producing a response | Use finite nginx `proxy_read_timeout`; allow expected finalization time |

Removing the whole-request deadline does **not** mean disabling every timeout.
However, it removes one resource-exhaustion safeguard, so inactivity and
concurrency controls become important.

## Proposed architecture

```text
Browser → upload-capable Traefik entrypoint → nginx upload proxy
        → MDR/Gunicorn → iRODS → ires
```

### Preferred isolation for ACC and production

Use a dedicated upload entrypoint/controller and upload hostname, with its
request-body read deadline disabled (`readTimeout: 0s`). Route it through nginx
to MDR. Keep ordinary application traffic on entrypoints with the existing
short read deadline.

Important implementation constraints:

- An HTTPRoute for `/dropzone_upload/` alone cannot select a different static
  read timeout on the same Traefik entrypoint.
- Two controllers cannot both bind the same node's host ports 80/443. A separate
  upload controller needs its own address, node placement, or load-balancer
  mapping. A second hostname alone does not provide timeout isolation.
- A new upload origin requires checking MDR's upload URL construction, session
  cookie scope, authentication, CSRF, CORS, and CSP. Do not assume the existing
  same-origin browser uploader will work unchanged.
- Any external load balancer, WAF, or firewall in front must also support long,
  actively streaming uploads. An outer fixed deadline still wins.

### Simpler shared-entrypoint alternative

If a separate upload origin is not feasible, disable Traefik's whole-request
read deadline on the shared entrypoints and place nginx in front of MDR under
the existing hostname. Use separate nginx locations for upload and normal
application requests.

This avoids browser-origin changes, but **does not preserve the 60-second outer
read deadline for other hosts** on those entrypoints. Those services need their
own appropriate protections. Choose this tradeoff explicitly, rather than
assuming nginx restores per-path Traefik deadlines.

## Nginx upload behavior

The legacy proxy configuration already provides a useful model:

<https://github.com/MaastrichtUniversity/docker-common/blob/main/proxy/app_mdr_prd.conf>

It disables request buffering and sets a body-size limit. Its `50000m` setting
is below the stated 150GB requirement, so do not copy that limit unchanged.

Illustrative upload location (not a complete deployable configuration):

```nginx
location /dropzone_upload/ {
    # Example: 150 GiB. Confirm whether the product limit is GB or GiB,
    # and allow for multipart overhead above the maximum file size.
    client_max_body_size 151g;

    # Stream to MDR; do not spool a 150GB request before forwarding it.
    proxy_request_buffering off;
    proxy_http_version 1.1;

    # Starting values for ACC testing, not established production settings.
    client_body_timeout 120s;
    proxy_connect_timeout 10s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;

    proxy_pass http://mdr.external.svc.cluster.local:8000;
}
```

These nginx timeouts apply between relevant successive I/O operations, not to
the complete upload duration. Validate their behavior during storage
backpressure and finalization; inactivity alone does not prove a request has
failed. `proxy_read_timeout` is not an overall application execution deadline.

The complete proxy configuration must also:

- Preserve the original Host and trusted forwarded HTTPS/client headers so
  Django still sees the correct public scheme and origin. Do not blindly trust
  client-supplied forwarded headers.
- Retain existing authentication, network restrictions, and rate limits.
- Avoid automatic replay/retry of partially streamed upload POST requests.
- Restrict direct access to MDR so the proxy's controls cannot be bypassed.
- Use bounded concurrent uploads and suitable proxy/MDR resource limits;
  request-rate limiting alone does not bound long-lived active uploads.
- Align application file-size validation with the proxy body-size limit.

## Application and operational follow-up

- Handle missing or interrupted multipart uploads explicitly in MDR instead of
  dereferencing `None`. Return an appropriate failure response.
- Define safe cleanup of abandoned `.part` objects. Never delete a partial
  object solely because it is old: an active large upload may also be old.
- Verify Gunicorn/gevent, iRODS clients, and storage operations do not introduce
  another incompatible deadline. Gunicorn's worker timeout is not necessarily
  a per-request duration limit for asynchronous workers.
- Add proxy access logs with duration, status, and request identifiers, and
  correlate them with MDR/iRODS errors. Avoid logging session credentials.
- Account for long uploads during rolling updates: finite termination grace
  periods can interrupt them. Plan draining or a maintenance procedure.
- Consider chunked/resumable uploads as a separate improvement; an extra proxy
  does not make interrupted uploads resumable.

## ACC validation before production

1. Review/render the proxy manifests and Ansible/Helm values; run server-side
   dry-run and diff against ACC. Verify Gateway route acceptance, selectors,
   ports, and NetworkPolicies before applying.
2. Confirm the upload entrypoint actually uses `readTimeout: 0s`, while normal
   entrypoints retain their intended settings in the isolated design.
3. Repeat the 1GiB upload with deliberate throttling so it exceeds 60 seconds
   and then one hour. Verify final object size and checksum against the source.
4. Test the agreed 150GB boundary, including multipart overhead, and rejection
   above the application limit. Check storage capacity first.
5. Pause or disconnect the sending client. Confirm the intended inactivity
   timeout, visible UI failure, and eventual safe partial-object cleanup.
6. Test unavailable MDR, storage backpressure, slow finalization, simultaneous
   uploads, and ordinary application failures. Verify failures are detected in
   the intended time rather than after an arbitrary hour.
7. Verify browser authentication and SAML still work, especially if introducing
   a separate upload origin. Test both upload and normal application routes.
8. Test proxy/controller rollouts with an active upload and document the
   interruption/draining behavior.

Promote only after these checks pass and the infrastructure diff is approved.
Keep changes in the Ansible-managed source, not only the live HelmChartConfig.

## Rollback

Retain the previous Helm/Ansible values and Gateway backend configuration.
Reverting the proxy route and values restores the old path, but also restores
its limitations: the 60-second default or the temporary one-hour upload cap.
Coordinate rollback with active uploaders; do not remove partial data as part
of infrastructure rollback.
