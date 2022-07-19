In this `patch/` directory we put files that we, DataHub, have patched
ourselves. Or `.patch` files.

* `add_ssl_setting_at_setup.patch`: This is a patch for `setup_irods.py` that
  comes with irods. It exists because there is currently no upstream way of
  installing an iRESC configured with an SSL-only iCAT.

  Reason is that `setup_irods.py` attempts to connect to the iCAT as part of
  the install process, but `setup_irods.py` (upstream) doesn't provide a way of
  adding SSL settings. These settings are expected to be set after install. But
  if your iCAT only accepts SSL connections (like our iCAT container), this
  will fail. This patch adds SSL settings during setup, so it can start talking
  SSL to iCAT from the get-go and not fail.
  Note: [see this commit for more](https://github.com/MaastrichtUniversity/docker-dev/commit/44efb62f1ac8bcec41134749a4be1f05a673b604)
