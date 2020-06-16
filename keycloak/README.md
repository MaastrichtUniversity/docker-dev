## Keycloak

Keycloak provides SAML authentication for Pacman. It also feeds the LDAP for iRODS authentication.

## Web interface
The webinterface is reachable (if your docker proxy is running) on: keycloak.${RIT_ENV}.dh.unimaas.nl

### Obtain realm export

To create a new realm-export.json, go to the keycloak web interface and use the export button at the bottom left.