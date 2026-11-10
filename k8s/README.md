# DataHub stack on Kubernetes

Kubernetes deployment for the stack previously run with `docker compose`
(`docker-compose.yml` + `docker-compose-irods.yml`). Target: a 3-node
**k3s** cluster with **Traefik** (Gateway API) and **Longhorn** storage.

**Status:** `dev` and `tst` overlays are complete and build-validated.
Still to come: `acc`/`prd` overlays (thin variants of tst), the
`Jenkinsfile.build`/`Jenkinsfile.deploy` pipelines, and the helper scripts
in `k8s/bin/` (see *Risks / open items*).

## How it works (30-second version)

```
browser / iRODS client
      |
Traefik on the nodes (:80 / :443)   <- Gateway API (not Ingress)
      |   one Gateway + HTTPRoute per public host,
      |   e.g. mdr.tst.dh.unimaas.nl
      v
Service in a namespace (mdr, elastic, davrods, keycloak, ...)
      v
pods in 4 namespaces:  irods / external / public / internal
```

- **Public traffic** enters through Traefik. Every public host has its own
  Gateway + HTTPRoute, placed in the namespace of the app it serves. tst
  terminates TLS with the multi-SAN `*.tst.dh.unimaas.nl` cert (from Vault);
  dev is HTTP-only, like the compose stack was.
- **iRODS data plane:** iCAT/iRES are StatefulSets behind *headless*
  Services. iRODS clients (mdr, davrods, admin-tools-backend, faker, ...)
  connect straight to the pod IP on the full 20000-20199 data-port range.
  The iRODS catalog stores Service FQDNs
  (`icat`/`ires-hnas-um`/`ires-hnas-azm`.`irods.svc.cluster.local`), which
  resolve from every namespace — this replaces the compose-era
  `*.dh.local` hostnames (no CoreDNS customization).
- **Storage:** Longhorn PVCs. Two StorageClasses: `longhorn-rwo` (default)
  and `longhorn-rwx` (for `staging-zones`, shared by both iRES pods + faker).
- **Configuration:** per-service env files in `overlays/<env>/config/`
  become ConfigMaps and are injected with `envFrom` — the same variables
  the compose services used, with k8s FQDNs where `.dh.local` used to be.
- **Secrets:**
  - **dev** — no Vault: kustomize generates the k8s Secrets at build time
    from committed files in `overlays/dev/secrets/` (same values as the
    compose `.env` / `irods.secrets.cfg`).
  - **tst (later acc/prd)** — the **ExternalSecrets operator** creates and
    keeps the same k8s Secrets in sync with Vault
    (`secret/datahub/<env>/...`). See *Deploying*, step 2.
- **Images:** the built app images are pulled from
  `registry.prod.dh.unimaas.nl/docker-dev/<name>:<tag>` (the base manifests
  reference them with that full registry path already). External base
  images (postgres/garage/openldap/nginx) are pulled from docker.io in dev
  and mirrored into the registry for tst+. No local builds at deploy time.

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
  base/                      # env-agnostic manifests
    <service>/               # one directory per service
    irods/config/            # vendored iRODS bootstrap + hooks (k8s variants)
    longhorn/                # StorageClasses
    faker/job-template.yaml  # on-demand faker Job template
    networkpolicies/         # optional segmentation (NOT applied by default)
  overlays/
    dev/                     # primary environment (what docker-dev used to be)
      config/*.env           # per-service env files -> ConfigMaps
      secrets/*.env          # dev-only: secret values -> Secrets (no Vault)
      gateway.yaml           # Gateway + HTTPRoute per public host (HTTP-only)
      namespaces.yaml
      kustomization.yaml     # generators, image registry + tags
    tst/                     # same shape, plus:
      external-secrets.yaml  # Vault -> k8s Secrets (ExternalSecrets operator)
      gateway.yaml           # + https listeners (multi-SAN cert via Vault)
    acc/ prd/                # TODO: thin variants of tst
  irods/k8s-ssl-certs/       # iRODS test certs (dev/tst), from bin/gen-irods-tls.sh
  bin/gen-irods-tls.sh       # iRODS TLS generator (test material only)
  Jenkinsfile.build          # TODO: build & push all images (pinned externals)
  Jenkinsfile.deploy         # TODO: kustomize build | kubectl apply
```

Build note: the base references repo files outside `k8s/base/`
(`irods/`, `keycloak/`, `ldap/`), so every build needs the
`--load-restrictor` flag:

```
kubectl kustomize k8s/overlays/dev --load-restrictor LoadRestrictionsNone
```

The **dev** overlay additionally needs an `externals/` checkout at the repo
root (epicpid SURF credentials are sourced from it; it is gitignored).
tst/acc/prd build in a clean clone — those creds come from Vault.

## Local dev on minikube (dev overlay)

The dev overlay targets a **local minikube cluster** (not k3s).
`overlays/dev/patches/` retargets every volume to minikube's `local-path`
StorageClass, shrinks them (~50Gi total), lowers CPU/memory (sum of all
pod requests: 2.45 CPU / 6.0Gi), and turns the shared ingest zones into a
hostPath `/staging-data` volume (single node = the compose-era host-dir
behavior). It is for validation and feature development, not load.

### One-time cluster setup

```
minikube start --cpus 4 --memory 8192 --disk-size 80
# (docker driver; the local-path StorageClass ships with minikube)

k8s/bin/minikube-traefik.sh
# enables the minikube loadbalancer addon (metallb), installs the
# Gateway API CRDs (v1.7.0) + Traefik v3.7 with the Gateway API provider
# + a LoadBalancer Service, then prints an /etc/hosts block for all 13
# dev public hosts. Re-runnable.

sudo tee -a /etc/hosts <<'EOF'
<LB-IP> app.mdr.dev.dh.unimaas.nl
... (the 13 hosts, printed by the script)
EOF
```

Alternative to the LB IP: `minikube tunnel` (needs sudo, docker driver)
serves cluster LoadBalancer traffic on `127.0.0.1` — then use
`127.0.0.1` in /etc/hosts. Note the Vite frontends enforce
`allowedHosts` = the public host name, so always access them through the
/etc/hosts names (a `localhost` Host header is rejected).

### Apply

```
kubectl kustomize k8s/overlays/dev --load-restrictor LoadRestrictionsNone | kubectl apply -f -
```

(Building dev requires an `externals/` checkout at the repo root — the
main tree has a symlink, a worktree does not by default.) Then Steps 4-5
of "Deploying (step by step)" apply (iRODS bootstrap, verify).

### Staging data (zones)

Both iress pods (and faker jobs, see below) share the minikube-VM
directory `/staging-data` via hostPath. Fresh cluster = empty, i.e. the
compose behavior of a clean `staging-data/`. To start from existing data
instead:

```
minikube start ... --mount --mount-string=$PWD/staging-data:/staging-data
```

### faker jobs on minikube

The faker job template mounts the `staging-zones` PVC; on minikube the
zones live on the hostPath, so apply it with the volume replaced
(`k8s/bin/faker.sh` will do this automatically for dev):

```
sed -e 's|^          persistentVolumeClaim:$|          hostPath:|' \
    -e 's|^            claimName: staging-zones$|            path: /staging-data\n            type: DirectoryOrCreate|' \
    k8s/base/faker/job-template.yaml | kubectl apply -f -
```

### dev secrets

`overlays/dev/secrets/irods-secrets-cfg.env` contains `<set-from-local-...>`
placeholders for the three vendor credentials (Atlassian API token,
BioPortal key, reCAPTCHA secret) instead of real values. Copy the real
ones from the local gitignored `irods.secrets.cfg` / `.env` (main tree)
before relying on those integrations.

## Deploying (step by step)

This section covers the k3s environments (tst/acc/prd); the local
minikube dev cluster has its own shorter path ("Local dev on
minikube").

### Prerequisites (per cluster, once)

1. 3-node k3s cluster, nodes >= 8C/32G (resource requests assume this).
2. Traefik with the **Gateway API** provider (k3s' Traefik; verify
   `kubectl get gatewayclass` shows `traefik`), :80/:443 reachable, and
   public DNS for `*.<env>.dh.unimaas.nl` pointing at the cluster.
3. Longhorn installed. Verify RWX volumes work on your Longhorn version
   (see Risks) — `staging-zones` needs `longhorn-rwx`.
4. Pull access to `registry.prod.dh.unimaas.nl` from all nodes (if the
   cluster is not already authenticated, create a
   `kubernetes.io/dockerconfigjson` secret per namespace and reference it
   via `imagePullSecrets`).
5. **tst/acc/prd only:** ExternalSecrets operator installed
   (external-secrets.io), and a Vault *kubernetes auth* role bound to the
   operator's service account with read access to `secret/datahub/<env>/*`.
6. The pre-existing ELK stack present in `monitoring`
   (filebeat outputs to `elk.monitoring.svc.cluster.local:5044`).
7. **Do not reuse compose-era storage:** the iRODS catalog bakes hostnames
   in at first bootstrap — a k8s env needs fresh PVCs/DBs (a reset is a
   clean re-bootstrap, see Day-2 operations).

### Step 1 — images in the registry

Until `Jenkinsfile.build` lands: make sure every image listed in
`overlays/<env>/kustomization.yaml` (`images:` section) exists in
`registry.prod.dh.unimaas.nl` at that name+tag. That means building with
the same Dockerfiles the compose repo uses (the `externals/*` checkouts)
and pushing under the registry names — including the mirrored base images
(postgres `17.10-alpine`, garage `v2.3.0`, openldap `1.3.0`, nginx
`alpine`). The Jenkins "datahub-images" pipeline replaces this step.

### Step 2 — secrets

**dev:** values are committed in `overlays/dev/secrets/` (same as the
compose `.env` / `irods.secrets.cfg`), except the three vendor
credentials in `irods-secrets-cfg.env` are `<set-from-local-irods-secrets.cfg>`
placeholders — fill them from the local gitignored files (see
"Local dev on minikube").

**tst:** provision Vault (KV v2), one path per k8s Secret, one Vault key
per Secret key (key names = the exact keys in the inventory table below):

```
secret/datahub/tst/dh                  25 keys  (see inventory: dh-secrets)
secret/datahub/tst/irods-secrets-cfg   14 keys + irods.secrets.cfg
secret/datahub/tst/irods-db            2 keys   (POSTGRES_PASSWORD, ENV_IRODS_DB_IRODS_PASSWORD)
secret/datahub/tst/mdr-db              1 key    (POSTGRES_PASSWORD)
secret/datahub/tst/admin-tools-db      1 key    (POSTGRES_PASSWORD)
secret/datahub/tst/epicpid             2 keys   (SURF pem file contents)
secret/datahub/tst/icat-tls            4 keys   (cert, key, dhparams, ca)
secret/datahub/tst/ires-um-tls         4 keys
secret/datahub/tst/ires-azm-tls        4 keys
secret/datahub/tst/garage1-tls         2 keys
secret/datahub/tst/garage2-tls         2 keys
secret/datahub/tst/ingress-tls         2 keys   (tls.crt = fullchain, tls.key)
```

Then fix the placeholders in `overlays/tst/external-secrets.yaml`: the
`dh-vault` ClusterSecretStore server URL and auth role. Notes:
- the `*-tls` paths can start with the test material from
  `irods/k8s-ssl-certs/` (its SANs are valid for every env); the CA key
  name must be `test_only_tst_irods_dh_ca_cert.pem` (matches
  `ENV_IRODS_SSL_CA_CERTIFICATE` in the env files).
- `ingress-tls` = the multi-SAN tst cert (what the Gateway https
  listeners terminate with).

### Step 3 — apply

```
kubectl kustomize k8s/overlays/<env> --load-restrictor LoadRestrictionsNone | kubectl apply -f -
```

This creates the 4 namespaces, all workloads/Services/ConfigMaps, the
Gateway/HTTPRoute objects, and (tst) the ExternalSecret resources. The
ExternalSecrets operator fills the Secrets within seconds —
`kubectl get externalsecret -A` should show every one `Ready=True`.

### Step 4 — first iRODS bootstrap (first deployment only, ~30 min)

The iRODS pods run a full bootstrap on first start
(`setup_irods.py` + ruleset compile + dev mockup):

```
kubectl -n irods get pods -w
```

`icat-0` becomes Ready first, then `ires-hnas-um-0`/`ires-hnas-azm-0`.
Pod restarts during this window are fine — the bootstrap is idempotent
(guarded by the state file persisted on the vault PVC + iCAT DB AVUs).
Troubleshooting: `kubectl -n irods logs <pod> --all-containers`, and check
the `irods-db` pod. Compose-era PVCs/DBs must not be mounted (old
hostnames).

### Step 5 — verify

```
kubectl get pods -A | grep -v ' Running'        # should (eventually) print nothing
# iRODS sanity (inside the icat pod):
kubectl -n irods exec icat-0 -- iadmin whoami
```

Public URLs (scheme per env: dev http, tst http+https where the cert
covers the host — see `overlays/<env>/gateway.yaml`):

| host | app |
|---|---|
| `<env>.dh.unimaas.nl` | dh-home |
| `mdr.<env>.dh.unimaas.nl` | mdr-home |
| `app.mdr.<env>.dh.unimaas.nl` | MDR app |
| `help.mdr.<env>.dh.unimaas.nl` | help-center (+ `/help_backend` API) |
| `download.`/`upload.<env>...` | DavRODS WebDAV |
| `keycloak.<env>...` / `admin.<env>...` | Keycloak / admin-tools |

### Day-2 operations (manual, until `k8s/bin/dhdev` lands)

```
# logs of any service
kubectl -n <ns> logs <pod>

# talk to a database
kubectl -n irods port-forward svc/irods-db 5432
kubectl -n external port-forward svc/mdr-db 5432

# run the faker job: copy the template, replace __NAME__ with a unique job
# name and __ARGS__ with a YAML flow list of faker args, then apply:
#   args: ["--remoteResource=ires-hnas-um.irods.svc.cluster.local", ...]
sed -e 's/__NAME__/faker-run1/' \
    -e 's/__ARGS__/["--remoteResource=ires-hnas-um.irods.svc.cluster.local"]/' \
  k8s/base/faker/job-template.yaml | kubectl -n irods apply -f -
# (bin/faker.sh will replace this; the Job's args annotation records them)

# change a config value: edit overlays/<env>/config/<svc>.env, re-apply
# (step 3). Generated ConfigMaps have stable names (no hash suffix), so a
# config change does NOT roll pods automatically - restart the affected
# workload: kubectl -n <ns> rollout restart deploy/<svc>
# (the FastAPI backends have AUTO_RELOAD for code, not env).

# reset iRODS (DESTRUCTIVE - fresh re-bootstrap):
kubectl -n irods delete pvc -l 'app.kubernetes.io/part-of=datahub' --force
kubectl -n irods scale --all --replicas=0        # then 1 again, in order
# (irods-db PVC included; equivalent of rit.sh reset-irods)
```

## Key decisions

### 1. `.dh.local` hostnames are renamed to native k8s Service names
The compose stack used `*.dh.local` hostnames (resolved by compose DNS).
On k8s we do **not** customize CoreDNS: every usage is a native Service
FQDN (`<svc>.<ns>.svc.cluster.local`, e.g. `icat.dh.local` ->
`icat.irods.svc.cluster.local`). Pod `hostname`/`HOSTNAME` on the iRODS
StatefulSets are the FQDNs (the bootstrap code reads
`socket.gethostname()`), the vendored hooks derive the physical resource
name from `ENV_IRODS_HOST_RESC_NAME`, and the iRODS TLS certs carry the
FQDN SANs. Full census: **`k8s/dh-local-worklist.md`** (sections A-C done).

### 2. iRODS data-port range (20000-20199)
A normal Service can't expose 200 ports (100-port limit). iCAT/iRES
therefore use **headless Services** (required for StatefulSets anyway):
the FQDNs resolve to the pod IP and the full port range is reachable
directly.

### 3. iRODS one-time bootstrap vs ephemeral pods
`/opt/irods/init.sh` runs `bootstrap.sh` (which runs `setup_irods.py`) on
**every** container start; only the pre/post hooks are gated on the state
file `/var/run/irods_installed`. Idempotency comes from:
- iCAT pre-hook: patches `setup_irods.py` when the DB is already populated,
- hook AVU guards (`bootstrap_irods_dev_mockup`), persisted in the iCAT DB.

So pod recreation re-runs the (guarded) bootstrap — same as today's
`down`+`up`. To make restarts *cheaper* and to keep the "installed" flag
honest, `/var/run/irods_installed` is additionally persisted on the vault
PVC (subPath). A reset = delete PVCs + re-bootstrap (see Day-2 ops;
`bin/irods-reset.sh` will automate it).

### 4. Ruleset & helpers
`make -C /rules` runs during bootstrap and needs the irods-ruleset +
irods-helper-cmd sources. The build pipeline bakes them into the iRODS
images (`k8s/images/irods/`, finalize stages over the dh-irods base
images — still to write). Dev iteration: `bin/ruleset-sync.sh` will copy a
local checkout into the pods and run `make` (replaces `rit.sh make rules`).

### 5. Garage
garage1/2 = Deployments + explicit PVCs (meta RWX so the bootstrap can
read node ids, data RWO). The layout/bucket/key setup runs in an init
container (idempotent; `layout assign/apply` guarded). Dependent pods
(garage*-s3-tls, ires-hnas-um) run an init container that *waits* for RPC
+ bucket instead of running the bootstrap (no races).

### 6. Images: registry, not local builds
Every built app image is pulled from
`registry.prod.dh.unimaas.nl/docker-dev/<name>:<tag>` — the base manifests
reference it with the full registry path.
- `Jenkinsfile.build` (TODO) clones each external repo at a pinned ref (or
  branch head for dev), builds with the same `--build-arg`s as compose, and
  pushes. External base images (postgres, openldap, nginx, garage) are
  mirrored into the registry too (for the k3s envs).
- External base images keep their docker.io names in the base manifests:
  dev pulls them from docker.io (local minikube, as the compose stack
  did); tst+ overlays rewrite them to the registry mirror via their
  `images:` section.
- Each overlay's `images:` transformer sets the tags for the built images
  (dev/tst default to `latest`; the deploy pipeline will override
  per-service with `kustomize --image`).
- Frontend images are built with `--target dev` for dev/tst (CRA dev
  server, as today) and `--target prd` for acc/prd (pipeline parameter).
- `keycloak/Dockerfile` bakes realm-export/users/import/startup/theme
  (previously bind-mounted).

### 7. Secrets & env
Per overlay: `configMapGenerator` (env files) + Secrets, consumed via
`envFrom`/volume mounts. Base references fixed names (see the inventory
below); overlays only decide *where the values come from*.

Two secret backends, same k8s Secret names:
- **dev** (no Vault): `secretGenerator` from committed files in
  `overlays/dev/secrets/` (iRODS TLS material from `irods/k8s-ssl-certs/`).
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
garage2-tls,ingress-tls}`.

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
| `ingress-tls` | kubernetes.io/tls (Gateway) | `tls.crt`, `tls.key` | Gateway https listeners (tst), via `certificateRefs` |

Notes:
- `PASSWORD`, `DB_PASSWORD`, `SECRET_KEY`, `POSTGRES_PASSWORD` are
  *container-expected* key names (each service reads its own name); in
  Vault they live under distinct paths, the mapping is in
  `external-secrets.yaml`.
- iRODS TLS: dev uses the committed test certs; `bin/gen-irods-tls.sh`
  generates the material (SANs = the k8s FQDNs, valid for every env; the
  `<ca>.pem` key name must match `ENV_IRODS_SSL_CA_CERTIFICATE`). prd:
  real PKI material.
- Gateway (public) TLS: dev is HTTP-only. tst uses the real multi-SAN
  `*.tst.dh.unimaas.nl` cert, stored in Vault under `ingress-tls` and
  materialized in the Gateway namespaces by the `ingress-tls`
  ExternalSecrets (the https listeners only cover the SANs the cert has —
  see `overlays/tst/gateway.yaml`). acc/prd: same pattern with their
  certs (a self-signed fallback would be `bin/gen-ingress-tls.sh`, still
  to write).

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
- dev (minikube): the same Gateway/HTTPRoute objects are served by a
  local Traefik installed by `bin/minikube-traefik.sh` (metallb LB IP in
  /etc/hosts, see "Local dev on minikube"); tst/acc/prd use the k3s
  Traefik.
- NetworkPolicies (default-deny + per-flow allows, incl. iRODS 20000-20199
  ranges and um<->azm isolation) live in `base/networkpolicies/` and are
  **not** applied by default: k3s must run with `--network-policy` for them
  to enforce. They still assume a single namespace and need reworking
  before use (see that file's header).

### 10. Probes
- postgres: `pg_isready` (readiness+liveness), chown init container.
- icat/ires: startup+readiness = `/dh_is_ready.sh` (mounted from the
  bootstrap ConfigMaps, as in compose), liveness = `iadmin whoami`
  (local-only). Startup window ~30 min (full bootstrap).
- keycloak: `/dh_is_ready.sh` (import state file).
- elastic/garage/nginx/ldap/apps: tcpSocket (no assumptions about images).

### 11. What intentionally drops
- Local bind-mount hot-reload (rule-wrapper, React `src`, sram-sync source,
  davrods app dir): replaced by pinned image builds (the CI/CD end-state).
  For hot dev iteration use `kubectl cp` + exec (see Day-2 operations).
- `/etc/localtime` mounts: replaced by `TZ` env.
- `staging-data/` host dirs: replaced by Longhorn PVCs (a
  `bin/seed-staging.sh` will seed the old fake data if wanted).

## Service -> workload map

| compose service      | k8s                          | storage            |
|----------------------|------------------------------|--------------------|
| irods-db             | StatefulSet + headless Svc   | 20Gi RWO           |
| icat                 | StatefulSet + headless Svc   | 50Gi RWO (vault+state) |
| ires-hnas-um         | StatefulSet + headless Svc   | 100Gi RWO (/mnt) + shared zones |
| ires-hnas-azm        | StatefulSet + headless Svc   | 100Gi RWO (/mnt) + shared zones |
| garage1 / garage2    | Deployment + Svc (bootstrap init ctr) | meta 10Gi RWX, data 100Gi RWO each |
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
| dh-faker             | on-demand Job (template in base) | shared zones  |

## Risks / open items
- **iRODS on k8s is still the fragile part**; first bring-up may need hook
  tweaks (the reset tooling + worklist ship for exactly that).
- **Not written yet:** `acc`/`prd` overlays (thin variants of tst),
  `Jenkinsfile.build`/`Jenkinsfile.deploy`, `k8s/bin/` helpers
  (`dhdev`, `faker.sh`, `ruleset-sync.sh`, `irods-reset.sh`,
  `seed-staging.sh`, `gen-ingress-tls.sh`), `k8s/images/irods/` finalize
  Dockerfiles, networkpolicy rework for the multi-namespace layout.
- Longhorn RWX: verify `numberOfReplicasRwx` works on your Longhorn version
  before relying on `staging-zones` (fallback: separate zone PVCs per ires).
- acc/prd TLS (iRODS CA + public cert) must come from real PKI; the scripts
  generate *test* material only.
- Resource requests assume >= 8C/32G per node; tune `base/**` as needed.
- tst `config/*.env` values are derived from the dev values (env-specific
  substitutions only) — verify per-service against the real tst stack when
  wiring up (LDAP DNs, SURF endpoints, JIRA/Confluence, ...).
