# SSL Notes

## Status: PoC. **Under development**
- `icat` and `ires` are SSL enabled and verify the certs, hostname included.
- Far from final form.
- Way of modifying irods configuration is not good. Just worried about making it work. Will be changed.
- *Only two* certs/keys under *icat*/SSL and *ires*/SSL. These are *not* final. Just testing. Will be deleted and replaced soon.
- *CA cert is not final*. We are just testing for now. Will be deleted/replaced
- We probably don't want any certs nor private keys publicly available. Even if they are for development only.
    - Could someone poison a developer's docker's internal DNS and MiM our irods connection?
    - We probably don't want to attract general searches for private keys here
    - Avoid warning from automated security tools
    * All above are not that important/likely, but as a matter of preference I would vote to keep them separately.

MDR works (rulewrapper does the iRODSSession..), but traffic is unencrypted (quickly checked with wireshark)
To force icat to always switch over to SSL maybe try:


In addition, change the catalog provider to require SSL for all connections.  Update the `/etc/irods/core.re` file to use `CS_NEG_REQUIRE` as follows:
```
    acPreConnect(*OUT) { *OUT="CS_NEG_REQUIRE"; }
```
From: https://github.com/irods-contrib/metalnx-web/blob/master/docs/PAM-%26-SSL-Configuration.md


## Plan:
- We create our own CA for dev purposes only: "iRODS Development/Testing Environment DataHub CA"
- We create certificates for icat , ires , ires-s3... And we sign these with the above mentioned CA
- We then load the certificate for the CA in the CA-rootstore of the containers that need to talk to irods (docker-dev)

#### This is just our dev environment, why do we need SSL here if everything happens locally (local containers talking to each other)?
True, but the goal with our dev environment is to resemble as closely as possible our production/acceptance environment. So having SSL here as well gets us closer to that goal.

#### But why our own CA? Wound't self-signed certs suffice?
If the goal was just having SSL we could just tell our iRODS containers to not verify the certs, and we could the same for the rest of the clients. But this widens the gap between our dev environment and our prod/acc environment.

If we create our own CA for this purpose, we would have the option of adding the certificate of this CA to the CA root store of the clients (also dev containers) that use these irods dev containers.

#### But why do we need to have the option to add it to the CA root-store of containers?
Again, this is due to us wanting to close that dev prod gap as much as possible. Having the certs be trusted without having to tweak the code in each container to tell it to use this CA or this self-signed cert, etc... is a big advantage.

#### Isn't it a **bad** idea to mess CA root-stores?
Yes, a compromised certificate in the CA root-store of a container compromises all TLS comms for that container. We can however do the following as extra mitigating measures:
	- If feasible, don't add it to the root trust-store and configure containers in dev environment via env variables in docker-compose
	- Use nameContraints for our dev/test CA to limit the domains it can sign certificates for.
		- Make this a critical extension (i.e. tell SSL libraries to fail if they haven't implemented this extension)
	- **WE WILL ONLY USE THIS CA FOR IRODS TEST/DEV CONTAINERS**

