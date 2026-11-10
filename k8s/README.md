# DataHub stack on Kubernetes

Kubernetes deployment for the stack previously run with `docker compose`
(`docker-compose.yml` + `docker-compose-irods.yml`). Target: a 3-node **k3s**
cluster with **Traefik** (in `traefik`) and **Longhorn** storage.

## Namespaces

Workloads live in logical namespaces (same layout for every env; base
manifests carry the namespace explicitly, overlays add the Namespace
objects):

| namespace    | workloads |
|--------------|-----------|
| `irods`      | irods-db, icat, ires-hnas-um/azm, garage1/2, garage1/2-s3-tls, epicpid, sram-sync, faker jobs |
| `external`   | mdr, mdr-db, mdr-home, elastic, davrods, davrods-upload |
| `public`     | dh-home, help-center, help-center-backend |
| `internal`   | keycloak, ldap, admin-tools, admin-tools-backend, admin-tools-db |
| `monitoring` | pre-existing ELK, reused as filebeat output (`elk.monitoring.svc.cluster.local`); Grafana/Loki later |

Consequences:
- ConfigMaps/Secrets are namespace-scoped, so every overlay generator is
  placed in the consuming namespace (`dh-secrets`/`dh-irods-secrets-cfg`
  exist in several).
- Gateway API (not Ingress) objects live in the namespace of the Services
  they route to: one Gateway + one HTTPRoute per public host
  (gatewayClassName `traefik`).
- Cross-namespace calls use Service FQDNs (see `dh-local-worklist.md`).

## Layout

```
k8s/
  base/                  # env-agnostic manifests (workloads, services, netpols)
    <service>/...        # one directory per service
    networkpolicies/     # optional segmentation (not applied by default)
  overlays/
    dev/                 # the primary environment (what docker-dev used to be)
      config/*.env       # per-env ConfigMap env files (envFrom)
      secrets/*.env      # dev-only: Secret env files (secretGenerator)
      tls/               # dev-only: test certs for the iRODS/garage TLS Secrets
      external-secrets.yaml  # tst/acc/prd: ExternalSecrets -> Vault (dev: absent)
      kustomization.yaml # namespace, images, generators
    tst/ acc/ prd/       # same shape; secrets come from Vault
  images/                # "finalize" Dockerfiles: bake ruleset/helpers into iRODS images
  bin/                   # helper scripts (up/down/test/logs/reset/tls)
  Jenkinsfile.build      # build & push all images
  Jenkinsfile.deploy     # kustomize build | kubectl apply
```

Deploy a single env (the base references files outside `k8s/base/`, so the
build needs `--load-restrictor LoadRestrictionsNone`; `bin/dhdev` wraps this):

```
kubectl kustomize k8s/overlays/dev --load-restrictor LoadRestrictionsNone | kubectl apply -f -
```

## Key decisions

### 1. `.dh.local` hostnames are renamed to native k8s Service names
The compose stack used `*.dh.local` hostnames (resolved by compose DNS).
On k8s we do **not** customize CoreDNS: every usage becomes the native
Service FQDN (`<svc>.<ns>.svc.cluster.local`, e.g.
`icat.dh.local` -> `icat.dh-dev.svc.cluster.local`). Headless Services
already make iCAT/iRES reachable on the 20000-20199 data range via pod IP.
The full census of `.dh.local` usages and the concrete work per item
(pod hostnames + cert re-issue, hook resource-name derivation, env values,
external-repo code) is in **`k8s/dh-local-worklist.md`** - execute once the
namespaces are finalized. Until then the base manifests still carry the
`.dh.local` hostnames.

### 2. iRODS data-port range (20000-20199)
A normal Service can't expose 200 ports (100-port limit). iCAT/iRES therefore
use **headless Services** (required for StatefulSets anyway): `.dh.local`
names resolve to the pod IP and the full port range is reachable directly.

### 3. iRODS one-time bootstrap vs ephemeral pods
`/opt/irods/init.sh` runs `bootstrap.sh` (which runs `setup_irods.py`) on
**every** container start; only the pre/post hooks are gated on the state
file `/var/run/irods_installed`. Idempotency comes from:
- iCAT pre-hook: patches `setup_irods.py` when the DB is already populated,
- hook AVU guards (`bootstrap_irods_dev_mockup`), persisted in the iCAT DB.

So pod recreation re-runs the (guarded) bootstrap — same as today's
`down`+`up`. To make restarts *cheaper* and to keep the "installed" flag
honest, we additionally persist `/var/run/irods_installed` on the vault PVC
(subPath). `bin/irods-reset.sh` wipes state (PVCs + state file + DB PVC) for
a clean re-bootstrap.

### 4. Ruleset & helpers
`make -C /rules` runs during bootstrap and needs the irods-ruleset +
irods-helper-cmd sources. The build pipeline bakes them into the iRODS images
(`k8s/images/irods/`, finalize stages over the dh-irods base images).
Dev iteration: `bin/ruleset-sync.sh` copies your local checkout into the pods
and runs `make` (replaces `rit.sh make rules`).

### 5. Garage
garage1/2 = Deployments + explicit PVCs (meta RWX so the init/bootstrap can
read node ids, data RWO). `garage-init` = a **Job** (one-time layout/bucket/
keys). Dependent pods (garage*-s3-tls, ires-hnas-um) run an init container
that *waits* for RPC + bucket instead of running the bootstrap (no races).
`irods/garage/bootstrap.sh` gained an idempotency guard around
`layout assign/apply`.

### 6. Images: registry, not local builds
Everything is pulled from `registry.prod.dh.unimaas.nl/docker-dev/<name>:<tag>`.
- `Jenkinsfile.build` clones each external repo at a pinned ref (or branch
  head for dev), builds with the same `--build-arg`s as compose, and pushes.
  External base images (postgres, openldap, nginx, garage) are mirrored too.
- Base manifests use neutral image names; each overlay's `images:` transformer
  sets registry + tag (e.g. `:latest` for dev, `:2026.11-<sha>` for CI tags).
- Frontend images are built with `--target dev` for dev/tst (CRA dev server,
  as today) and `--target prd` for acc/prd (pipeline parameter).
- `keycloak/Dockerfile` now bakes realm-export/users/import/startup/theme
  (previously bind-mounted).

### 7. Secrets & env
Per overlay: `configMapGenerator` (env files) + Secrets, consumed via
`envFrom`/volume mounts. Base references fixed names (see the inventory
below); overlays only decide *where the values come from*.

Two secret backends, same k8s Secret names:
- **dev** (no Vault): `secretGenerator` from committed files in
  `overlays/dev/secrets/` + `overlays/dev/tls/` (the repo's test certs).
- **tst/acc/prd** (Vault): **ExternalSecrets Operator**
  (`external-secrets.io/v1`). Each overlay ships `external-secrets.yaml`
  (one `ExternalSecret` per k8s Secret) + a `ClusterSecretStore`
  (`dh-vault`) pointing at Vault. The operator creates/refreshes the k8s
  Secrets with exactly the names the base manifests reference. Do not
  combine both backends for the same Secret name in one env.
  ExternalSecret `data:` mappings in `overlays/<env>/external-secrets.yaml`
  use **placeholder Vault paths** (`secret/datahub/<env>/...`) - adjust to
  your actual Vault layout when you wire it up.

Suggested Vault layout (KV v2, one path per k8s Secret, one key per
Secret key): `secret/datahub/<env>/{dh,irods-db,mdr-db,admin-tools-db,
irods-secrets-cfg,epicpid,icat-tls,ires-um-tls,ires-azm-tls,garage1-tls,
garage2-tls}`.

**Inventory of every Secret the base manifests reference** (this is the
list to provision in Vault):

| Secret | Kind | Keys | Consumed by |
|---|---|---|---|
| `dh-secrets` | Opaque (env) | `ENV_IRODS_PASSWORD_ADMIN`, `IRODS_PASS`, `ENV_IRODS_KEY_SERVER_ZONE`, `ENV_IRODS_KEY_SERVER_NEGOTIATION`, `ENV_IRODS_KEY_CONTROL_PLANE`, `ENV_IRODS_PASSWORDS_SALT`, `ENV_IRODS_DB_IRODS_PASSWORD`, `ENV_IRODS_DB_POSTGRES_PASSWORD`, `GARAGE_RPC_SECRET`, `GARAGE_ADMIN_TOKEN`, `ENV_S3_ACCESS_KEY_AC`, `ENV_S3_SECRET_KEY_AC`, `ENV_S3_ACCESS_KEY_GL`, `ENV_S3_SECRET_KEY_GL`, `ELASTIC_PASSWORD`, `PASSWORD` (epicpid), `KEYCLOAK_PASSWORD`, `LDAP_ADMIN_PASSWORD`, `LDAP_PASS` (sram-sync), `DB_PASSWORD` (admin-tools-backend), `MDR_POSTGRES_PASSWORD`, `DJANGO_SECRET_KEY`, `SECRET_KEY` (admin-tools-backend), `AIRFLOW_API_KEY`, `OIDC_CLIENT_SECRET` | icat, ires-um, ires-azm (+init ctrs), garage1/2, irods-db, ldap, keycloak, mdr, elastic, epicpid, sram-sync, admin-tools-backend, faker |
| `irods-db-credentials` | Opaque (env) | `POSTGRES_PASSWORD`, `ENV_IRODS_DB_IRODS_PASSWORD` | irods-db |
| `mdr-db-credentials` | Opaque (env) | `POSTGRES_PASSWORD` | mdr-db |
| `admin-tools-db-credentials` | Opaque (env) | `POSTGRES_PASSWORD` | admin-tools-db |
| `dh-irods-secrets-cfg` | Opaque (env + file) | env: `INGEST_PASSWORD`, `INGEST_USER`, `INGEST_MOUNT`, `LDAP_PASSWORD`, `LDAP_USER`, `LDAP_URL`, `LDAP_DOMAIN`, `USE_SAMBA`, `DATAVERSE_TOKEN`, `BIOPORTAL_API_KEY`, `ATLASSIAN_API_USERNAME`, `ATLASSIAN_API_KEY`, `REACT_APP_CAPTCHA_SECRET_KEY`, `REACT_APP_CAPTCHA_SITE_KEY`; file: `irods.secrets.cfg` | mdr, ires-um, ires-azm (env + `/etc/secrets` file), help-center-backend, admin-tools-backend, help-center (env) |
| `epicpid-credentials` | Opaque (files) | `305_21_T12996_USER01_UM_privkey.pem`, `305_21_T12996_USER01_UM_certificate_only.pem` | epicpid (mounted at `/opt/app/credentials`) |
| `icat-tls` | Opaque (files) | `icat.dh.local.crt`, `icat.dh.local.key`, `dhparams.pem`, `<ca>.pem` | icat (`/opt/irods_ssl_staging`) |
| `ires-um-tls` | Opaque (files) | `ires-hnas-um.dh.local.crt`, `ires-hnas-um.dh.local.key`, `dhparams.pem`, `<ca>.pem` | ires-hnas-um (`/opt/irods_ssl_staging`) |
| `ires-azm-tls` | Opaque (files) | `ires-hnas-azm.dh.local.crt`, `ires-hnas-azm.dh.local.key`, `dhparams.pem`, `<ca>.pem` | ires-hnas-azm (`/opt/irods_ssl_staging`) |
| `garage1-tls` | Opaque (files) | `garage1.dh.local.crt`, `garage1.dh.local.key` | garage1-s3-tls nginx (`/etc/nginx/certs`) |
| `garage2-tls` | Opaque (files) | `garage2.dh.local.crt`, `garage2.dh.local.key` | garage2-s3-tls nginx (`/etc/nginx/certs`) |

Notes:
- `PASSWORD`, `DB_PASSWORD`, `SECRET_KEY`, `POSTGRES_PASSWORD` are
  *container-expected* key names (each service reads its own name); in
  Vault they live under distinct paths, the mapping is in
  `external-secrets.yaml`.
- iRODS TLS: dev uses the committed test certs; `bin/gen-irods-tls.sh`
  generates per-env certs (needed to populate Vault for tst/acc/prd; the
  `<ca>.pem` key name must match `ENV_IRODS_SSL_CA_CERTIFICATE`).
- Ingress (Gateway) TLS: dev is HTTP-only (as the compose stack was).
  tst uses the real multi-SAN `*.tst.dh.unimaas.nl` cert, stored in Vault
  under `ingress-tls` and materialized per Gateway namespace by the
  `ingress-tls` ExternalSecrets (type `kubernetes.io/tls`; the Gateway
  `https` listeners only cover the SANs the cert has - see
  `overlays/tst/gateway.yaml`). acc/prd: same pattern with their certs
  (a self-signed fallback would be `bin/gen-ingress-tls.sh`, still to
  write).

### 8. Storage (Longhorn)
Two StorageClasses: `longhorn-rwo` (default) and `longhorn-rwx`
(NFS-backed, for `staging-zones` shared by both iRES pods + faker).
3 nodes -> `numberOfReplicas: "2"`.

### 9. Networking
- Traefik **Gateway API** (gatewayClassName `traefik`) per overlay for all
  `*.<env>.dh.unimaas.nl` hosts (replaces the docker-common nginx proxy
  incl. SAML browser redirect). One Gateway + one HTTPRoute per public
  host, in the namespace of the backend Service. The cluster does not use
  the Ingress resource.
- No `hostPort`s; dev access to DBs via `kubectl port-forward`.
- NetworkPolicies (default-deny + per-flow allows, incl. iRODS 20000-20199
  ranges and um<->azm isolation) live in `base/networkpolicies/` and are
  **not** applied by default: k3s must run with `--network-policy` for them
  to enforce. Enable by adding the dir to an overlay.

### 10. Probes
- postgres: `pg_isready` (readiness+liveness), chown init container.
- icat/ires: startup+readiness = `/dh_is_ready.sh` (dev overrides from
  ConfigMaps, as in compose), liveness = `iadmin whoami` (local-only).
  Startup window ~30 min (full bootstrap).
- keycloak: `/dh_is_ready.sh` (import state file).
- elastic/garage/nginx/ldap/apps: tcpSocket (no assumptions about images).

### 11. What intentionally drops
- Local bind-mount hot-reload (rule-wrapper, React `src`, sram-sync source,
  davrods app dir): replaced by pinned image builds (the CI/CD end-state).
  For hot dev iteration use `kubectl cp` + exec (see `bin/`).
- `/etc/localtime` mounts: replaced by `TZ` env.
- `staging-data/` host dirs: replaced by Longhorn PVCs (seed with
  `bin/seed-staging.sh` if you want the old fake data).

## Service -> workload map

| compose service      | k8s                          | storage            |
|----------------------|------------------------------|--------------------|
| irods-db             | StatefulSet + headless Svc   | 20Gi RWO           |
| icat                 | StatefulSet + headless Svc   | 50Gi RWO (vault+state) |
| ires-hnas-um         | StatefulSet + headless Svc   | 100Gi RWO (/mnt) + shared zones |
| ires-hnas-azm        | StatefulSet + headless Svc   | 100Gi RWO (/mnt) + shared zones |
| garage1 / garage2    | Deployment + Svc             | meta 10Gi RWX, data 100Gi RWO each |
| garage-init          | Job                          | (state in garage PVCs) |
| garage1/2-s3-tls     | Deployment + Svc (:9000)     | - (init-wait)      |
| ldap                 | Deployment + Svc             | 2Gi RWO            |
| keycloak             | Deployment + Svc             | -                  |
| mdr                  | Deployment + Svc             | 10Gi RWO (static)  |
| mdr-db               | StatefulSet + headless Svc   | 10Gi RWO           |
| admin-tools-db       | StatefulSet + headless Svc   | 5Gi RWO            |
| elastic              | Deployment + Svc             | 20Gi RWO           |
| davrods / -upload    | Deployment + Svc (:80)       | -                  |
| epicpid              | Deployment + Svc             | (creds Secret)     |
| sram-sync            | Deployment (`--scheduled`)   | -                  |
| help-center-backend, admin-tools-backend | Deployment + Svc | -      |
| help-center, dh-home, mdr-home, admin-tools | Deployment + Svc (:3000) | - |
| dh-faker             | on-demand Job (`bin/faker.sh`) | shared zones  |

## Operational runbook (replaces rit.sh flows)

```
# build+push images        -> Jenkins "datahub-images" pipeline
# deploy env               -> Jenkins "datahub-deploy" (or kubectl apply -k)
./k8s/bin/dhdev up dev             # apply overlays + wait for iRODS ready
./k8s/bin/dhdev down dev           # scale down / delete
./k8s/bin/dhdev logs dev icat
./k8s/bin/dhdev test dev irods     # pytest in icat pod (as rit.sh test)
./k8s/bin/dhdev make-rules dev     # rebuild ruleset in icat+ires pods
./k8s/bin/dhdev faker dev <args>   # run the faker job
./k8s/bin/dhdev reset-irods dev    # destructive: re-bootstrap iRODS
```

## Risks / open items
- iRODS on K8s is still the fragile part; first bring-up may need hook
  tweaks (that's why `k8s/bin` + reset tooling ships alongside).
- `numberOfReplicasRwx` on Longhorn: verify RWX works on your Longhorn
  version before relying on `staging-zones` (fallback: separate zone PVCs).
- acc/prd TLS (iRODS CA + ingress) must come from the real PKI; scripts
  generate *test* material only.
- Resource requests assume >=8C/32G per node; tune `base/**` as needed.
