# iRODS ruleset snapshot

`irods-ruleset.tar.gz.b64` is the compressed, base64-encoded source snapshot
mounted at `/rules` for ICAT and iRES on Kubernetes. The ICAT init container unpacks it
into a pod-local `emptyDir`, matching the Docker Compose bind mount
`externals/irods-ruleset:/rules`.

The checked-in snapshot is sourced from `externals/irods-ruleset`; local rule
changes must be included when refreshing the snapshot.

To reload local rule changes into the running TST pods without restarting them:

```sh
./rit.sh make rules k8s
```

This also refreshes the ConfigMap snapshot used by newly created pods. Set
`K8S_NAMESPACE` to override the default `irods` namespace. Without the `k8s`
argument, `./rit.sh make rules` keeps its existing Docker Compose behavior.
