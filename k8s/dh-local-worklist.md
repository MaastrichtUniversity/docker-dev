# Worklist: replace `.dh.local` names with native k8s service names

Decision: **no CoreDNS rewrite/customization.** Every `.dh.local`
hostname used by the compose stack must become the native k8s name of the
corresponding Service. This list is the complete census (tracked files in
this repo + `externals/` checkouts + image-baked config) with the concrete
work per item. Execute **after the namespaces are finalized**, since the
target FQDN embeds the namespace.

Workloads live in logical namespaces (finalized, same for every env):

| namespace    | workloads |
|--------------|-----------|
| `irods`      | irods-db, icat, ires-hnas-um/azm, garage1/2, garage1/2-s3-tls, epicpid, sram-sync, faker jobs |
| `external`   | mdr, mdr-db, mdr-home, elastic, davrods, davrods-upload |
| `public`     | dh-home, help-center, help-center-backend |
| `internal`   | keycloak, ldap, admin-tools, admin-tools-backend, admin-tools-db |
| `monitoring` | pre-existing ELK (not deployed by us; filebeat targets `elk.monitoring.svc.cluster.local`) |

Cluster domain: `cluster.local` (k3s default).

## Name mapping

| compose name              | k8s replacement                          | Service type |
|---------------------------|------------------------------------------|--------------|
| `icat.dh.local`           | `icat.irods.svc.cluster.local`           | headless (pod IP, 20000-20199) |
| `ires-hnas-um.dh.local`   | `ires-hnas-um.irods.svc.cluster.local`   | headless (pod IP, 20000-20199) |
| `ires-hnas-azm.dh.local`  | `ires-hnas-azm.irods.svc.cluster.local`  | headless (pod IP, 20000-20199) |
| `irods-db.dh.local`       | `irods-db.irods.svc.cluster.local`       | headless     |
| `mdr-db.dh.local`         | `mdr-db.external.svc.cluster.local`      | headless     |
| `admin-tools-db.dh.local` | `admin-tools-db.internal.svc.cluster.local` | headless  |
| `ldap.dh.local`           | `ldap.internal.svc.cluster.local`        | ClusterIP    |
| `elastic.dh.local`        | `elastic.external.svc.cluster.local`     | ClusterIP    |
| `keycloak.dh.local`       | `keycloak.internal.svc.cluster.local`    | ClusterIP    |
| `epicpid.dh.local`        | `epicpid.irods.svc.cluster.local`        | ClusterIP    |
| `admin-tools-backend.dh.local` | `admin-tools-backend.internal.svc.cluster.local` | ClusterIP |
| `garage1.dh.local`        | `garage1-s3-tls.irods.svc.cluster.local` | ClusterIP (:9000 TLS) |
| `garage2.dh.local`        | `garage2-s3-tls.irods.svc.cluster.local` | ClusterIP (:9000 TLS) |
| `elk.dh.local`            | `elk.monitoring.svc.cluster.local`       | (pre-existing) |
| `ires-ceph-ac.dh.local` / `ires-ceph-gl.dh.local` | fictitious (hosts-hack only, see A5) | - |

Single-label names (`ldap`, `garage1`, `mdr-db`, ...) already resolve
natively **within the same namespace** via CoreDNS search domains - those
usages need no change (section F). All remaining cross-namespace traffic
uses the FQDNs above.

## A. iRODS pod identity & hooks (the invasive part)

Status: **A1-A4 and C(dev) are done** in `k8s/base`; **B is done for dev
and tst** (acc/prd overlays still to write); the remaining work is D
(external follow-ups).

1. **[done] Force hostname** - `spec.hostname` + `HOSTNAME` env on the three
   iRODS StatefulSets are now the headless Service FQDNs
   (`icat.irods.svc.cluster.local`, `ires-hnas-{um,azm}.irods...`).
   `gen_json_configuration.py` takes `irods_host` / `catalog_provider_hosts`
   from `socket.gethostname()` -> follows the hostname automatically
   (verified in
   `externals/dh-irods/irods-base/scripts/lib/gen_json_configuration.py`).
2. **[done] Re-issued iRODS TLS certs** - `bin/gen-irods-tls.sh` generates
   CA + 5 leaves with the new SANs into `irods/k8s-ssl-certs/` (dev,
   committed like the compose `test-dev-ssl-certs`). File *names* changed
   (`icat.crt` ...), but the TLS Secret *keys* keep the old names
   (`icat.dh.local.crt`) so `ENV_IRODS_SSL_CERT/KEY/CA` and the garage
   nginx confs are unchanged - only SAN/CN matter.
3. **[follows] iCAT catalog resource hosts**: `mkresc ... unixfilesystem
   ${HOSTNAME}:/...` bakes the ires FQDN into the catalog at first
   bootstrap; iRODS clients in *other* namespaces (mdr, sram-sync, faker,
   admin-tools-backend, davrods) connect to that host on 20000-20199 -
   headless Service FQDN resolves to the pod IP. **Compose-era PVCs/DBs
   contain the old hosts and must NOT be reused.**
4. **[done] Resource-name derivation** - hooks are now vendored k8s copies
   (`k8s/base/irods/config/hooks-{icat,ires}/`; the base kustomization
   points at them, compose keeps the originals). `bootstrap_irods.sh`
   (ires, 7 places) uses `ENV_IRODS_HOST_RESC_NAME` instead of
   `${HOSTNAME%%.dh.local}Resource`; overlays set it
   (`ires-hnas-umResource` / `ires-hnas-azmResource` - identical to the
   names the compose stack produced, so ruleset/MDR expectations are
   unchanged). icat hooks: no derivation found, copied verbatim.
5. **[done, resolved differently] pre-hook `/etc/hosts` hack** - removed
   from the vendored ires pre-hook instead of ported: on k3s both ires
   pods are genuinely reachable, so pinning the peer to a dead IP would
   *break* legitimate UM<->AZM replication. The fictitious
   `ires-ceph-{ac,gl}` names (pre-ceph->garage leftovers, referenced by
   nothing current) are gone with it. No `hostAliases` needed.

## B. Per-env values (overlay `config/*.env` only - no code changes)

Status: **[done for dev + tst]** `k8s/overlays/dev/config/` (file-based
secrets) and `k8s/overlays/tst/config/` (derived: `.tst.dh.unimaas.nl`
hosts, `ENV=RIT_ENV=ENV_ENVIRONMENT=tst`, `DJANGO_DEV_MODE=False`,
`GARAGE_BUCKET=dh-irods-bucket-tst`, CA key name
`test_only_tst_irods_dh_ca_cert.pem`, SMB ingest zones `/tst`; all other
values = dev values as placeholders - verify per-service against the real
tst stack when wiring up). tst secrets come from Vault via
`k8s/overlays/tst/external-secrets.yaml` (placeholder paths).

| env key | compose value | k8s value |
|---|---|---|
| `ENV_IRODS_ICAT_HOST` | `icat.dh.local` | `icat.irods.svc.cluster.local` |
| `IRODS_HOST` (mdr, sram-sync, admin-tools-backend, faker) | `icat.dh.local` | `icat.irods.svc.cluster.local` |
| `IRODS_SERVER` (davrods, davrods-upload) | `icat.dh.local` | `icat.irods.svc.cluster.local` |
| `ENV_IRODS_DB_HOSTNAME` | `irods-db.dh.local` | `irods-db.irods.svc.cluster.local` |
| `MDR_POSTGRES_HOST` | `mdr-db.dh.local` | `mdr-db.external.svc.cluster.local` |
| `DB_HOST` (admin-tools-backend) | `admin-tools-db.dh.local` | `admin-tools-db.internal.svc.cluster.local` |
| `ELASTIC_HOST` / `ENV_ELASTIC_HOST` (mdr, elastic, iRODS json) | `elastic.dh.local` | `elastic.external.svc.cluster.local` |
| `LDAP_HOST` (sram-sync) | `ldap://ldap.dh.local` | `ldap://ldap.internal.svc.cluster.local` |
| `ENV_S3_HOST_AC` | `garage1.dh.local:9000` | `garage1-s3-tls.irods.svc.cluster.local:9000` |
| `ENV_S3_HOST_GL` | `garage2.dh.local:9000` | `garage2-s3-tls.irods.svc.cluster.local:9000` |
| `ENV_EPICPID_URL` | `http://epicpid.dh.local/epic/21.T12996/` | `http://epicpid.irods.svc.cluster.local/epic/21.T12996/` |
| `ENV_FILEBEAT_HOST` (new; iRODS + any filebeat output) | `elk.dh.local` (hardcoded in filebeat.yml) | `elk.monitoring.svc.cluster.local` |
| faker job `remoteResource` arg | `ires-hnas-um.dh.local` | `ires-hnas-um.irods.svc.cluster.local` |
| ires bootstrap dockerize wait default | `icat.dh.local` (default only) | covered by `ENV_IRODS_ICAT_HOST` |

Also: `k8s/base/**` comments/`-icat.dh.local` fallbacks in the
`wait-icat` init containers follow `ENV_IRODS_ICAT_HOST` already.

## C. TLS re-issue

- **[done]** `bin/gen-irods-tls.sh`: new SANs per A2 (5 leaf certs + CA +
  dhparams), run for dev, output committed to `irods/k8s-ssl-certs/`.
  acc/prd: same script with a per-env SAN suffix if the namespaces ever
  differ, or real PKI material.
- `bin/gen-ingress-tls.sh`: still to write (public `*.<env>.dh.unimaas.nl`;
  dev is HTTP-only for now).

## D. External repos (real code/config changes needed)

1. **dh-admin-tools frontend, prd target** (`.nginx/nginx.conf`):
   `resolver 127.0.0.11` (Docker DNS - dead in k8s) +
   `server admin-tools-backend.dh.local:8000 resolve`.
   - Mitigation in place: the Ingress already splits `/api` ->
     admin-tools-backend, so this upstream is never hit from the browser.
   - Proper fix (follow-up): template the upstream FQDN + cluster DNS IP at
     build time (per-env build arg) or change the repo to read them.
2. **filebeat outputs `elk.dh.local:5044`** (dh-irods base, dh-mdr,
   rit-davrods x2, dh-admin-tools x2, dh-help-center frontend): the ELK
   stack is reused from the **monitoring** namespace
   (`elk.monitoring.svc.cluster.local:5044`; to be replaced by
   Grafana/Loki later).
   - iRODS (done): vendored bootstraps sed the host from
     `ENV_FILEBEAT_HOST` (set in `irods-common-env` per overlay).
   - remaining (follow-up, needs image/externals change): dh-mdr,
     rit-davrods, dh-admin-tools, dh-help-center frontends - until then
     their filebeat keeps retrying against `elk.dh.local` (harmless).
3. **irods-ruleset `utils/createFakeFiles.r` / `createFakeTapeFile.r`**:
   `remoteResource="ires-hnas-um.dh.local"` is a *caller argument*, not a
   default -> no repo change; `bin/faker.sh`/`faker-env` must pass the new
   FQDN (see B).
4. **dh-irods test scripts** (`tests/dt_dev_icat.sh`, `tests/prod_icat.sh`):
   `irods-db.dh.local` -> update when `bin/dhdev test` is implemented.
5. **dh-irods `default_general_json_configuration.json`**: template values
   (`icat.dh.local`, `irods-db.dh.local`, `epicpid.dh.local`,
   `elastic.dh.local`) are **overridden at bootstrap** by
   `gen_json_configuration.py` from envs (A1 + B) -> no change needed.

## E. Ingress / public URLs - no change

All `*.<env>.dh.unimaas.nl` hosts (incl. SAML/OIDC metadata URLs in mdr
envs and keycloak) stay public and are served by the Ingress.

## F. Already k8s-compatible (no work, recorded for the record)

- keycloak `realm-export.json`: `ldap://ldap` - single-label, resolves via
  CoreDNS search domains in the same namespace.
- garage tomls: `rpc_public_addr = "garage1:3901"` / `"garage2:3901"` -
  same-namespace short names.
- `dh-admin-tools/backend/app/utilities/vars.py`: `DB_HOST` default
  `admin-tools-db.dh.local` - env-overridden (B).
- `dh-irods/ires-hnas/scripts/bootstrap.sh`: dockerize default
  `icat.dh.local` - env-overridden (B).
- README/docs: dh-mdr README + CI workflow, sram-sync README, dh-irods
  README, irods-rule-wrapper tests README - docs only.

## G. Ordering & prerequisites

1. Namespaces finalized (this list's FQDNs).
2. First iRODS bootstrap happens with the new names on fresh PVCs
   (never reuse compose-era PVCs/DBs - old hosts baked in catalog).
3. A4 (hook vendoring) + A1 (hostname) + A2 (certs) must land **together**
   - a half-renamed iRODS stack won't pass its own TLS checks.
4. Then B (env files), C (scripts), D (follow-ups), and the `bin/` tools
   (dhdev test/faker) get the new names.
