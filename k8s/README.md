# DataHub stack on Kubernetes

Kubernetes deployment for the stack previously run with `docker compose`
(`docker-compose.yml` + `docker-compose-irods.yml`). Target: a 3-node **k3s**
cluster with **Traefik** (in `traefik`) and **Longhorn** storage.

## Layout

```
k8s/
  base/                  # env-agnostic manifests (workloads, services, netpols)
    <service>/...        # one directory per service
    networkpolicies/     # optional segmentation (not applied by default)
  overlays/
    dev/                 # the primary environment (what docker-dev used to be)
      config/*.env       # per-env ConfigMap env files (envFrom)
      secrets/*.env      # per-env Secret env files
      cluster/           # cluster-scoped: coredns-custom (kube-system)
      kustomization.yaml # namespace, images, generators
    tst/ acc/ prd/       # same shape; fill in real credentials
  images/                # "finalize" Dockerfiles: bake ruleset/helpers into iRODS images
  bin/                   # helper scripts (up/down/test/logs/reset/tls)
  Jenkinsfile.build      # build & push all images
  Jenkinsfile.deploy     # kustomize build | kubectl apply
```

Deploy a single env: `kubectl apply -k k8s/overlays/dev` (plus the
cluster-scoped `k8s/overlays/dev/cluster`).

## Key decisions

### 1. `.dh.local` hostnames are kept, resolved via CoreDNS rewrite
iRODS bakes `*.dh.local` hostnames into the iCAT catalog (resource hosts),
SSL certs (already committed in `irods/*/test-dev-ssl-certs/`) and scripts
(resource names are derived as `${HOSTNAME%%.dh.local}Resource`). Renaming
would force cert re-issue and script surgery. Instead, a **`coredns-custom`**
ConfigMap in `kube-system` (the documented k3s extension point) adds a
`dh.local` server block that rewrites known names to cluster Service DNS:

```
icat.dh.local        -> icat.<ns>.svc.cluster.local        (headless -> pod IP)
ires-hnas-um.dh.local-> ires-hnas-um.<ns>.svc.cluster.local (headless -> pod IP)
ires-hnas-azm.dh.local-> ...same
garage1.dh.local     -> garage1-s3-tls.<ns>.svc...   (nginx TLS :9000)
garage2.dh.local     -> garage2-s3-tls...
ldap.dh.local, mdr-db.dh.local, admin-tools-db.dh.local,
irods-db.dh.local, elastic.dh.local, keycloak.dh.local -> same-named Services
```

Constraint: **one environment per cluster** (the rewrite is cluster-global).
If multiple envs ever share a cluster, they need distinct suffixes.

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
Per overlay: `secretGenerator` (credentials) + `configMapGenerator`
(env files), consumed via `envFrom`. Base references fixed names
(`dh-irods-secrets`, `<svc>-env`, ...). Dev values mirror the current
`.env`/`irods.secrets.cfg`; **TST/ACC/PRD files are placeholders to fill**
(and eventually source from your secret store).
iRODS TLS certs: dev uses the committed test certs; `bin/gen-irods-tls.sh`
generates per-env certs + Secrets (needed for tst/acc/prd).
Ingress TLS: wildcard `*.<env>.dh.unimaas.nl` self-signed via
`bin/gen-ingress-tls.sh` (trust the CA in browsers; internal traffic stays
HTTP, as today).

### 8. Storage (Longhorn)
Two StorageClasses: `longhorn-rwo` (default) and `longhorn-rwx`
(NFS-backed, for `staging-zones` shared by both iRES pods + faker).
3 nodes -> `numberOfReplicas: "2"`.

### 9. Networking
- Traefik Ingress (class `traefik`) per overlay for all `*.<env>.dh.unimaas.nl`
  hosts (replaces the docker-common nginx proxy incl. SAML browser redirect).
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
