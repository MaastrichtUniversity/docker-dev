# DataHub stack on Kubernetes

Kubernetes deployment for the stack previously run with `docker compose`
(`docker-compose.yml` + `docker-compose-irods.yml`). Target: a 3-node
**k3s** cluster with **Traefik** (Gateway API) and **Longhorn** storage.

**Status:** `dev` and `tst` overlays are complete and build-validated.
Still to come: `acc`/`prd` overlays (thin variants of tst), the
`Jenkinsfile.build`/`Jenkinsfile.deploy` pipelines, and the helper scripts
in `k8s/bin/` (see _Risks / open items_).

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
- **iRODS data plane:** iCAT/iRES are StatefulSets behind _headless_
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
    from scoped files in `overlays/dev/secrets/` (only each workload's
    required keys; secret vendor values remain placeholders until copied
    from local gitignored config).
  - **tst (later acc/prd)** — the **ExternalSecrets operator** creates and
    keeps the same k8s Secrets in sync with Vault
    (`secret/datahub/<env>/...`). See _Deploying_, step 2.
- **Images:** the built app images are pulled from
  `registry.prod.dh.unimaas.nl/docker-dev/<name>:<tag>` (the base manifests
  reference them with that full registry path already). External base
  images (postgres/garage/openldap/nginx) are pulled from docker.io in dev
  and mirrored into the registry for tst+. No local builds at deploy time.

## Namespaces

Workloads live in logical namespaces (same layout for every env; base
manifests carry the namespace explicitly, overlays add the Namespace
objects):

| namespace    | workloads                                                                                            |
| ------------ | ---------------------------------------------------------------------------------------------------- |
| `irods`      | irods-db, icat, ires-hnas-um/azm, garage1/2, garage1/2-s3-tls, epicpid, sram-sync, faker jobs        |
| `external`   | mdr, mdr-db, mdr-home, elastic, davrods, davrods-upload                                              |
| `public`     | dh-home, help-center, help-center-backend                                                            |
| `internal`   | keycloak, ldap, admin-tools, admin-tools-backend, admin-tools-db                                     |
| `monitoring` | pre-existing ELK, reused as filebeat output (`elk.monitoring.svc.cluster.local`); Grafana/Loki later |

Consequences:

- ConfigMaps/Secrets are namespace-scoped, so every generator/ExternalSecret
  is placed in the consuming namespace; credentials are split by workload
  rather than copied as a complete set into every namespace.
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
      secrets/*.yaml         # Vault -> k8s Secrets (ExternalSecrets operator)
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
root (epicpid SURF credentials are sourced from it; it is gitignored):
`k8s/bin/dhdev.sh externals` creates it. tst/acc/prd build in a clean
clone — those creds come from Vault.

## Local dev on minikube (dev overlay)

The dev overlay targets a **local minikube cluster** (not k3s).
`overlays/dev/patches/` retargets every volume to minikube's `standard`
StorageClass, shrinks them (~50Gi total), lowers CPU/memory (sum of all
pod requests: 2.45 CPU / 6.0Gi), and turns the shared ingest zones into a
hostPath `/staging-data` volume (single node = the compose-era host-dir
behavior). It is for validation and feature development, not load.

### Spin up

```
k8s/bin/dhdev.sh dev-up
```

That is the whole flow:

1. `externals/` at the repo root — created/cloned/pulled if needed
   (same repo list as the compose repo's `rit.sh`; see the SURF note
   below)
2. minikube started if not running: `--cpus 4 --memory 8192
--disk-size 80` (docker driver)
3. the `storage-provisioner` and `default-storageclass` addons are enabled;
   the script verifies the `standard` StorageClass before applying PVCs
4. `k8s/bin/minikube-traefik.sh`: minikube loadbalancer addon (metallb),
   Gateway API CRDs (v1.7.0), Traefik v3.7 with the Gateway API provider
   - LoadBalancer Service, CoreDNS rewrite for `*.local.dh.unimaas.nl`,
   and it prints an `/etc/hosts` block for all 13 dev public hosts
5. `k8s/bin/dhdev.sh pull-external` and `k8s/bin/dhdev.sh build`: `pull-external`
   pre-pulls upstream external images (`postgres`, `garage`, `openldap`, `nginx`,
   `traefik`) into minikube's Docker daemon, and `build` builds all compose
   images directly inside minikube's Docker daemon using
   `registry.prod.dh.unimaas.nl/docker-dev/*:latest` tags (matching `rit.sh`), so
   images can be pushed when needed without pulling from the remote registry
   (`patches/images-dev.yaml` sets `imagePullPolicy: Never` across all workloads
   and removes `imagePullSecrets`). Pass `--no-build` to `dev-up` to skip
   building, or run `k8s/bin/dhdev.sh build [service...]` to rebuild individual
   images.
6. the dev overlay is applied and the PVCs are checked

Then add the printed /etc/hosts block:

```
sudo tee -a /etc/hosts <<'EOF'
<LB-IP> app.mdr.local.dh.unimaas.nl
... (the 13 hosts, printed by the script)
EOF
```

Steps 4-5 of "Deploying (step by step)" then apply (iRODS bootstrap,
verify). Re-run `dev-up` after a `git pull` to roll out changes.

`k8s/bin/dhdev.sh externals` alone just (re)creates `externals/`. Note:
the epicpid SURF credentials
(`externals/epicpid-microservice/credentials/*.pem`) are **not in the
public epicpid-microservice repo** — the script detects when they are
missing and tells you to copy them from an existing checkout (e.g. your
compose tree).

Alternative to the LB IP: `minikube tunnel` (needs sudo, docker driver)
serves cluster LoadBalancer traffic on `127.0.0.1` — then use
`127.0.0.1` in /etc/hosts. Note the Vite frontends enforce
`allowedHosts` = the public host name, so always access them through the
/etc/hosts names (a `localhost` Host header is rejected).

### Deploy profiles

Not every workload is needed for every kind of development.
`dev-up --profile minimal` applies only the compose "minimal" set
(iRODS development): irods-db, icat, ires-hnas-um, garage1/2 (+s3-tls),
keycloak, ldap, epicpid, elastic, mdr-db, mdr, sram-sync.

```
k8s/bin/dhdev.sh dev-up --profile minimal   # iRODS core + auth only
k8s/bin/dhdev.sh dev-up                     # full stack (default)
```

The full-only workloads (ires-hnas-azm, davrods, davrods-upload,
help-center, help-center-backend, dh-home, mdr-home, admin-tools,
admin-tools-backend, admin-tools-db) carry the label
`datahub.dh/profile: full` in the base manifests, and `dev-up` applies
through a label selector — so the profile lists can't drift from the
manifests, and the script prints what it skips. Switching
full -> minimal does not delete the already-running full-only workloads;
re-run `dev-up` without `--profile` to bring them back.

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

The dev secrets files contain `<set-from-local-...>` placeholders for
vendor credentials (Atlassian API token, BioPortal key, reCAPTCHA secret)
instead of real values. They are split by consumer across
`irods-secrets-cfg.env`, `mdr-app-secrets.env`,
`admin-tools-secrets.env`, and `help-center-secrets.env`. Copy the real
values from the local gitignored `irods.secrets.cfg` / `.env` (main tree)
into each relevant file before relying on those integrations; don't commit
local credential values.

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
   (external-secrets.io), and Vault *kubernetes auth* configured at mount
   `<env>-k3s` (e.g. `tst-k3s`) bound to the central `vault-auth` service account
   in the `external-secrets` namespace with read access to `<env>/*`.
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

**dev:** scoped values are in `overlays/dev/secrets/`; the vendor API
credentials are placeholders in the consumer-specific secret files. Fill
them from the local gitignored `.env`/`irods.secrets.cfg` before relying on
those integrations (see "Local dev on minikube").

**tst:** provision Vault (KV v2 mount `tst`), one path per k8s Secret under
`tst/data/tst-k3s/<secret>` (see the inventory table below for full key details):

```
tst/data/tst-k3s/icat-app-secrets       iRODS zone & database credentials (clean keys, no ENV_)
tst/data/tst-k3s/garage-secrets         Garage credentials & S3 keys (reused by ires)
tst/data/tst-k3s/epicpid-app-secrets    epicpid application password (PASSWORD)
tst/data/tst-k3s/sram-sync-secrets      LDAP bind password for sram-sync (LDAP_PASS)
tst/data/tst-k3s/irods-secrets-cfg      14 integration keys + raw irods.secrets.cfg (reused across stacks)
tst/data/tst-k3s/epicpid                2 SURF PEM file contents
tst/data/tst-k3s/elastic-secrets        ELASTIC_PASSWORD
tst/data/tst-k3s/mdr-app-secrets        MDR backend passwords (MDR_POSTGRES_PASSWORD, DJANGO_SECRET_KEY)
tst/data/tst-k3s/admin-tools-secrets    Admin Tools backend secrets (DB_PASSWORD, OIDC_CLIENT_SECRET, etc.)
tst/data/tst-k3s/keycloak-secrets       KEYCLOAK_PASSWORD
tst/data/tst-k3s/ldap-secrets           LDAP_ADMIN_PASSWORD
tst/data/tst-k3s/icat-tls               icat.dh.local.{crt,key}, dhparams.pem, ca.pem
tst/data/tst-k3s/ires-um-tls            ires-hnas-um.dh.local.{crt,key}, dhparams.pem, ca.pem
tst/data/tst-k3s/ires-azm-tls           ires-hnas-azm.dh.local.{crt,key}, dhparams.pem, ca.pem
tst/data/tst-k3s/garage1-tls            garage1.dh.local.{crt,key}
tst/data/tst-k3s/garage2-tls            garage2.dh.local.{crt,key}
tst/data/tst-k3s/gateway-tls            tls.crt (fullchain), tls.key
```

**Importing TLS & dhparams into Vault:**
Diffie-Hellman parameters do not expire and can be generated once (via Ansible or
`openssl dhparam -2 -out dhparams.pem 2048`). Import the certificates and `dhparams.pem`
(from `irods/k8s-ssl-certs/` or your PKI) into Vault using the Vault CLI:

```bash
CERTS_DIR="irods/k8s-ssl-certs"

# iCAT TLS
vault kv put tst/tst-k3s/icat-tls \
  icat.dh.local.crt=@${CERTS_DIR}/icat.crt \
  icat.dh.local.key=@${CERTS_DIR}/icat.key \
  dhparams.pem=@${CERTS_DIR}/dhparams.pem \
  test_only_tst_irods_dh_ca_cert.pem=@${CERTS_DIR}/ca.pem

# iRES TLS (UM & AZM)
vault kv put tst/tst-k3s/ires-um-tls \
  ires-hnas-um.dh.local.crt=@${CERTS_DIR}/ires-hnas-um.crt \
  ires-hnas-um.dh.local.key=@${CERTS_DIR}/ires-hnas-um.key \
  dhparams.pem=@${CERTS_DIR}/dhparams.pem \
  test_only_tst_irods_dh_ca_cert.pem=@${CERTS_DIR}/ca.pem

vault kv put tst/tst-k3s/ires-azm-tls \
  ires-hnas-azm.dh.local.crt=@${CERTS_DIR}/ires-hnas-azm.crt \
  ires-hnas-azm.dh.local.key=@${CERTS_DIR}/ires-hnas-azm.key \
  dhparams.pem=@${CERTS_DIR}/dhparams.pem \
  test_only_tst_irods_dh_ca_cert.pem=@${CERTS_DIR}/ca.pem

# Garage S3 TLS
vault kv put tst/tst-k3s/garage1-tls \
  garage1.dh.local.crt=@${CERTS_DIR}/garage1.crt \
  garage1.dh.local.key=@${CERTS_DIR}/garage1.key

vault kv put tst/tst-k3s/garage2-tls \
  garage2.dh.local.crt=@${CERTS_DIR}/garage2.crt \
  garage2.dh.local.key=@${CERTS_DIR}/garage2.key

# Gateway Ingress TLS (multi-SAN *.tst.dh.unimaas.nl cert)
vault kv put tst/tst-k3s/gateway-tls \
  tls.crt=@/path/to/tst-fullchain.pem \
  tls.key=@/path/to/tst-privkey.pem
```

The `vault-auth.yaml` manifest defines the cluster-wide `ClusterSecretStore` (`dh-vault`),
the `external-secrets` namespace, the central `vault-auth` ServiceAccount, and the TokenReview
ClusterRoleBinding (`system:auth-delegator`).

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

| host                                   | app                                 |
| -------------------------------------- | ----------------------------------- |
| `<env>.dh.unimaas.nl`                  | dh-home                             |
| `mdr.<env>.dh.unimaas.nl`              | mdr-home                            |
| `app.mdr.<env>.dh.unimaas.nl`          | MDR app                             |
| `help.mdr.<env>.dh.unimaas.nl`         | help-center (+ `/help_backend` API) |
| `download.`/`upload.<env>...`          | DavRODS WebDAV                      |
| `keycloak.<env>...` / `admin.<env>...` | Keycloak / admin-tools              |

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
`down`+`up`. To make restarts _cheaper_ and to keep the "installed" flag
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
(garage*-s3-tls, ires-hnas-um) run an init container that _waits_ for RPC

- bucket instead of running the bootstrap (no races).

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
below); overlays only decide _where the values come from_.

Two secret backends, same k8s Secret names:

- **dev** (no Vault): `secretGenerator` from committed files in
  `overlays/dev/secrets/` (iRODS TLS material from `irods/k8s-ssl-certs/`).
- **tst/acc/prd** (Vault): **ExternalSecrets Operator**
  (`external-secrets.io/v1`). Each overlay ships `secrets/*.yaml`
  (one `ExternalSecret` per k8s Secret, mirroring `overlays/dev/secrets/`)
  and `vault-auth.yaml` which defines the
  `ClusterSecretStore` (`dh-vault`), the central `vault-auth` ServiceAccount in
  namespace `external-secrets`, and the TokenReview RBAC. The operator
  creates/refreshes the k8s Secrets across all namespaces with exactly the names
  the base manifests reference. Credential Secrets are scoped to namespace and
  consumer; in particular the public Help Center backend receives only its
  Atlassian/CAPTCHA credentials, not the iRODS, Garage, or database credentials.

Vault layout (KV v2 mount `tst`, path prefix `tst-k3s/<secret>`):
`<mount>/data/<cluster>/<secret>` containing the exact keys listed in the inventory
table below. Each application path contains only the keys that workload consumes.

**Inventory of every Secret the base manifests reference** (this is the
list to provision in Vault):

| Secret                                    | Kind                        | Keys                                                                                                                | Consumed by                                          |
| ----------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `icat-app-secrets` (irods)                | Opaque (env)                | `IRODS_PASSWORD_ADMIN`, `IRODS_PASS`, `IRODS_KEY_SERVER_ZONE`, `IRODS_KEY_SERVER_NEGOTIATION`, `IRODS_KEY_CONTROL_PLANE`, `IRODS_PASSWORDS_SALT`, `IRODS_DB_IRODS_PASSWORD`, `IRODS_DB_POSTGRES_PASSWORD` | icat, ires-hnas-um, ires-hnas-azm, irods-db, faker   |
| `garage-secrets` (irods)                  | Opaque (env)                | `GARAGE_RPC_SECRET`, `GARAGE_ADMIN_TOKEN`, `S3_ACCESS_KEY_AC`, `S3_SECRET_KEY_AC`, `S3_ACCESS_KEY_GL`, `S3_SECRET_KEY_GL` | Garage workloads + ires (um & azm) S3 credentials   |
| `dh-irods-secrets-cfg` (irods)            | Opaque (env + file)         | Full iRODS cfg env set + `irods.secrets.cfg` file                                                                   | ires-um, ires-hnas-azm                               |
| `epicpid-app-secrets` (irods)             | Opaque (env)                | `PASSWORD`                                                                                                          | epicpid                                              |
| `epicpid-credentials` (irods)             | Opaque (files)              | `305_21_T12996_USER01_UM_privkey.pem`, `305_21_T12996_USER01_UM_certificate_only.pem`                               | epicpid (mounted at `/opt/app/credentials`)          |
| `sram-sync-secrets` (irods)               | Opaque (env)                | `LDAP_PASS`                                                                                                         | sram-sync                                            |
| `icat-tls` (irods)                        | Opaque (files)              | `icat.dh.local.crt`, `icat.dh.local.key`, `dhparams.pem`, `<ca>.pem`                                                | icat (`/opt/irods_ssl_staging`)                      |
| `ires-um-tls` (irods)                     | Opaque (files)              | `ires-hnas-um.dh.local.crt`, `ires-hnas-um.dh.local.key`, `dhparams.pem`, `<ca>.pem`                                | ires-hnas-um (`/opt/irods_ssl_staging`)              |
| `ires-azm-tls` (irods)                    | Opaque (files)              | `ires-hnas-azm.dh.local.crt`, `ires-hnas-azm.dh.local.key`, `dhparams.pem`, `<ca>.pem`                              | ires-hnas-azm (`/opt/irods_ssl_staging`)             |
| `garage1-tls` (irods)                     | Opaque (files)              | `garage1.dh.local.crt`, `garage1.dh.local.key`                                                                      | garage1-s3-tls nginx (`/etc/nginx/certs`)            |
| `garage2-tls` (irods)                     | Opaque (files)              | `garage2.dh.local.crt`, `garage2.dh.local.key`                                                                      | garage2-s3-tls nginx (`/etc/nginx/certs`)            |
| `mdr-app-secrets` (external)              | Opaque (env)                | `MDR_POSTGRES_PASSWORD`, `DJANGO_SECRET_KEY` (+ vendor keys from `irods-secrets-cfg`)                               | mdr backend & mdr-db                                 |
| `elastic-secrets` (external)              | Opaque (env)                | `ELASTIC_PASSWORD`                                                                                                  | elastic                                              |
| `admin-tools-secrets` (internal)          | Opaque (env)                | `DB_PASSWORD`, `OIDC_CLIENT_SECRET`, `SECRET_KEY`, `AIRFLOW_API_KEY` (+ vendor keys from `irods-secrets-cfg`)       | admin-tools-backend & admin-tools-db                 |
| `keycloak-secrets` (internal)             | Opaque (env)                | `KEYCLOAK_PASSWORD`                                                                                                 | keycloak                                             |
| `ldap-secrets` (internal)                 | Opaque (env)                | `LDAP_ADMIN_PASSWORD`                                                                                               | ldap                                                 |
| `help-center-secrets` (public)            | Opaque (env)                | `ATLASSIAN_API_USERNAME`, `ATLASSIAN_API_KEY`, `REACT_APP_CAPTCHA_SECRET_KEY` (all from `irods-secrets-cfg`)        | help-center-backend only                             |
| `frontend-public-config` (public)         | Opaque (env)                | `REACT_APP_CAPTCHA_SITE_KEY` (from `irods-secrets-cfg`, public site key)                                            | public frontends                                     |
| `gateway-tls` (external, public, internal)| kubernetes.io/tls (Gateway) | `tls.crt`, `tls.key`                                                                                                | Gateway https listeners (tst), via `certificateRefs` |
| `registry-credentials` (irods, external, public, internal) | kubernetes.io/dockerconfigjson (`ClusterExternalSecret`) | `.dockerconfigjson` (extracted from `tst-k3s/registry-credentials`) | Cluster-wide registry pull secret (`imagePullSecrets`) |

Notes:

- **Clean secret keys (no `ENV_` prefix):** Secret keys in Vault and k8s Secrets
  do not use the legacy `ENV_` prefix (e.g. `IRODS_PASSWORD_ADMIN`, `S3_ACCESS_KEY_AC`).
  Workload manifests (`statefulset.yaml`, `deployments.yaml`) use explicit `secretKeyRef`
  to map them to the `ENV_*` environment variable names expected by internal container
  scripts (e.g. `gen_json_configuration.py`, `create_icat_db.sh`).
- `PASSWORD`, `DB_PASSWORD`, `SECRET_KEY`, `POSTGRES_PASSWORD` are
  _container-expected_ key names; in Vault they live under distinct secret paths,
  and `secrets/*.yaml` references each path.
- iRODS TLS: dev uses the committed test certs; `bin/gen-irods-tls.sh`
  generates the material (SANs = the k8s FQDNs, valid for every env; the
  `<ca>.pem` key name must match `ENV_IRODS_SSL_CA_CERTIFICATE`). prd:
  real PKI material.
- Gateway (public) TLS: dev is HTTP-only. tst uses the real multi-SAN
  `*.tst.dh.unimaas.nl` cert, stored in Vault under `gateway-tls` and
  materialized in the Gateway namespaces by the `gateway-tls`
  ExternalSecrets (the https listeners only cover the SANs the cert has —
  see `overlays/tst/gateway.yaml`). acc/prd: same pattern with their
  certs (a self-signed fallback would be `bin/gen-gateway-tls.sh`, still
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

| compose service                             | k8s                                   | storage                            |
| ------------------------------------------- | ------------------------------------- | ---------------------------------- |
| irods-db                                    | StatefulSet + headless Svc            | 20Gi RWO                           |
| icat                                        | StatefulSet + headless Svc            | 50Gi RWO (vault+state)             |
| ires-hnas-um                                | StatefulSet + headless Svc            | 100Gi RWO (/mnt) + shared zones    |
| ires-hnas-azm                               | StatefulSet + headless Svc            | 100Gi RWO (/mnt) + shared zones    |
| garage1 / garage2                           | Deployment + Svc (bootstrap init ctr) | meta 10Gi RWX, data 100Gi RWO each |
| garage1/2-s3-tls                            | Deployment + Svc (:9000)              | - (init-wait)                      |
| ldap                                        | Deployment + Svc                      | 2Gi RWO                            |
| keycloak                                    | Deployment + Svc                      | -                                  |
| mdr                                         | Deployment + Svc                      | 10Gi RWO (static)                  |
| mdr-db                                      | StatefulSet + headless Svc            | 10Gi RWO                           |
| admin-tools-db                              | StatefulSet + headless Svc            | 5Gi RWO                            |
| elastic                                     | Deployment + Svc                      | 20Gi RWO                           |
| davrods / -upload                           | Deployment + Svc (:80)                | -                                  |
| epicpid                                     | Deployment + Svc                      | (creds Secret)                     |
| sram-sync                                   | Deployment (`--scheduled`)            | -                                  |
| help-center-backend, admin-tools-backend    | Deployment + Svc                      | -                                  |
| help-center, dh-home, mdr-home, admin-tools | Deployment + Svc (:3000)              | -                                  |
| dh-faker                                    | on-demand Job (template in base)      | shared zones                       |

## Risks / open items

- **iRODS on k8s is still the fragile part**; first bring-up may need hook
  tweaks (the reset tooling + worklist ship for exactly that).
- **Not written yet:** `acc`/`prd` overlays (thin variants of tst),
  `Jenkinsfile.build`/`Jenkinsfile.deploy`, `k8s/bin/` helpers
  (`dhdev`, `faker.sh`, `ruleset-sync.sh`, `irods-reset.sh`,
  `seed-staging.sh`, `gen-gateway-tls.sh`), `k8s/images/irods/` finalize
  Dockerfiles, networkpolicy rework for the multi-namespace layout.
- Longhorn RWX: verify `numberOfReplicasRwx` works on your Longhorn version
  before relying on `staging-zones` (fallback: separate zone PVCs per ires).
- acc/prd TLS (iRODS CA + public cert) must come from real PKI; the scripts
  generate _test_ material only.
- Resource requests assume >= 8C/32G per node; tune `base/**` as needed.
- tst `config/*.env` values are derived from the dev values (env-specific
  substitutions only) — verify per-service against the real tst stack when
  wiring up (LDAP DNs, SURF endpoints, JIRA/Confluence, ...).
