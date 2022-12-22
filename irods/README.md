# iRODS development environment

Our iRODS dev env is based on dh-irods.

`dh-irods` allows for hooks to customize iRODS further. We leverage this to
carry out actions differently in development than in production. In
development, for example, we create a series of mock projects, collections and
users.

The hooks are to be named `bootstrap_pre_hook.sh` and `bootstrap_post_hook.sh`,
and to be placed in `/opt/irods/hooks/` inside the container. `dh-irods` will
read them and execute them if they exist.

Each of these {`icat`, `ires-hnas`, `ires-s3`} has their own tuple of
(`bootstrap_pre_hook.sh`, `bootstrap_post_hook.sh`). For instance,
`ires-hnas`'s hooks can be found under `./ires-hnas/hooks/`.

We use these hooks here in development like this:
* `bootstrap_pre_hook.sh`: Depends on which {`icat`, `ires-hnas`,
  `ires-s3`}, but generally we use it to create physical resources
  (`mkdir`) that in production already exists and are mounted, or.. what
  have ya.
* `bootstrap_post_hook.sh`: Here we generally call our `bootstrap_irods.sh`
  which takes care of creating fake projects, collections, etc..

In development, we also want to have some "fake" SSL certificates that we sign
with our own "fake" (for iRODS testing purposes only) CA. These files, for
instance, live under `./ires-hnas/test-dev-ssl-certs/`. Having SSL in
development allows us to closer reassemble our production infrastructure.

We also need the database 'icat' and user 'irods' to already exist in postgres.
We do that via `irods-db/create_icat_db.sh`. This is something `setup_irods.py`
expects.

