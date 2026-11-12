## Keycloak

Keycloak provides SAML authentication for MDR. It also feeds the LDAP for iRODS authentication.

## Web interface
The webinterface is reachable (if your docker proxy is running) on: keycloak.${RIT_ENV}.dh.unimaas.nl

### Obtain realm export

To create a new realm-export.json, go to the keycloak web interface and use the export button at the bottom left.

### Startup and fixture passwords

Startup waits for Keycloak's HTTP endpoint, logs in once, creates the `django`
realm if needed, synchronizes LDAP once, and sets fixture passwords through the
Admin REST API. It fetches LDAP user IDs with one wildcard query; no per-user
Java CLI processes are launched. Password updates still go through Keycloak's
writable LDAP provider and are repeated on startup, including for an existing
realm or LDAP database.

The fixture password defaults to `foobar` in `import.sh`. Existing Jenkins
substitution remains supported:

```sh
sed -i "s/foobar/$DEMO_KEYCLOAK_PASSWORD/g" keycloak/import.sh
```

Alternatively, export `DEMO_KEYCLOAK_PASSWORD` before invoking `rit.sh`; Compose
passes it to Keycloak. A nonempty environment value takes precedence over the
script default, including a default changed by Jenkins. This also supports
passwords containing quotes, slashes, ampersands or dollar signs without editing
shell source. `KEYCLOAK_PASSWORD` remains the separate administrator password.

Readiness requires a completed import and a responding realm HTTP endpoint.
An import error records `failed`; `rit.sh` checks every two seconds, stops on
failure or an exited container, and limits its wait to five minutes. Startup
clears the previous marker before launching the background import.

Run the localhost HTTP regression tests with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s keycloak -p 'test_*.py'
```
