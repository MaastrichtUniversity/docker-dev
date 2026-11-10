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

1. **Force hostname** (`base/{icat,ires-hnas-um,ires-hnas-azm}/statefulset.yaml`):
   `spec.hostname` + `HOSTNAME` env currently `<name>.dh.local` -> change to
   the mapped FQDN (namespace known per overlay; add a kustomize patch per
   overlay or template via the env file + `fieldRef`-free patch).
   - `gen_json_configuration.py` takes `irods_host` /
     `catalog_provider_hosts` from `socket.gethostname()` -> follows the
     hostname automatically (verified in
     `externals/dh-irods/irods-base/scripts/lib/gen_json_configuration.py`).
2. **Re-issue iRODS TLS certs** for the new SANs (CN must equal the new
   hostname; `ENV_IRODS_SSL_*` + cert secret keys).
   - File *names* can stay (e.g. `icat.dh.local.crt`) - only the SAN/CN
     matters; keeping the names avoids touching the nginx confs and the
     `ENV_IRODS_SSL_CERT/KEY/CA` values. `bin/gen-irods-tls.sh` must take
     the new SANs.
   - Affected: `icat-tls`, `ires-um-tls`, `ires-azm-tls`, `garage1-tls`,
     `garage2-tls` Secrets.
3. **iCAT catalog resource hosts**: `mkresc ... unixfilesystem
   ${HOSTNAME}:/...` bakes the ires hostname into the catalog; iRODS
   clients in *other* pods (mdr, sram-sync, faker, admin-tools-backend,
   davrods) then connect to that host on 20000-20199. The headless Service
   FQDN resolves to the pod IP -> works. No extra work beyond A1/A2, but
   **the catalog is built at first bootstrap** - old compose-era PVCs/DBs
   contain the old hosts and must NOT be reused (reset required).
4. **Resource-name derivation `${HOSTNAME%%.dh.local}Resource`** breaks
   with FQDN hostnames. Occurrences (shared hook files, currently
   ConfigMap-sourced from `irods/*/hooks/`):
   - `irods/ires-hnas/hooks/bootstrap_irods.sh`: `create_mock_projects_*`
     (x4 rule calls), `iadmin modresc ... comment`, `imeta add -R`,
     `iadmin modresc ... path` (~7 places).
   - `irods/icat/hooks/bootstrap_irods.sh`: same pattern (verify count).
   - Work: vendor k8s copies of the hooks into `k8s/base/irods/config/`
     (like the bootstrap scripts) and replace the derivation with an
     explicit env, e.g. `ENV_IRODS_HOST_RESC_NAME=ires-hnas-umResource`
     (set per overlay in `ires-*-env`). Check the ruleset/MDR expectations
     for the physical resource name (`ires-hnas-umResource`) stay identical.
5. **pre-hook `/etc/hosts` hack** (`irods/ires-hnas/hooks/bootstrap_pre_hook.sh`
   ~L55-59): pins the *other* ires host (+fictitious ceph hosts) to
   172.0.0.x so clients fail fast instead of timing out. Work: replace with
   native k8s `hostAliases:` on both ires StatefulSets (new FQDNs, same
   fictitious IPs); drop the ceph entries or keep them fictitious under new
   names. Then the hook change disappears (or the vendored hook copy keeps
   them with new names - pick one, don't do both).

## B. Per-env values (overlay `config/*.env` only - no code changes)

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

## C. TLS re-issue (script work)

- `bin/gen-irods-tls.sh`: new SANs per A2 (5 leaf certs + CA + dhparams).
- `bin/gen-ingress-tls.sh`: unchanged (public `*.<env>.dh.unimaas.nl`).

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
