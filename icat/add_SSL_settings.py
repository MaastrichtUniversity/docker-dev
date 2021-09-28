#!/usr/bin/env python
import json

SSL_settings = {
    "irods_ssl_certificate_chain_file": "/etc/irods/SSL/irods.dh.local.crt",
    "irods_ssl_certificate_key_file": "/etc/irods/SSL/irods.dh.local.key",
    "irods_ssl_ca_certificate_file": "/etc/irods/SSL/test_only_dev_irods_dh_ca_cert.pem",
    "irods_ssl_dh_params_file": "/etc/irods/SSL/dhparams.pem",
    "irods_client_server_policy": "CS_NEG_REQUIRE",
    "irods_host": "irods.dh.local",
#    "irods_ssl_verify_server": "none",
#    "irods_ssl_verify_server": "cert",
    "irods_ssl_verify_server": "hostname",
#    "irods_log_level": 7
}

with open("/var/lib/irods/.irods/irods_environment.json", "r+") as irods_json_file:
    irods_env_data = json.load(irods_json_file)
    irods_env_data.update(SSL_settings)
    irods_json_file.seek(0)
    json.dump(irods_env_data, irods_json_file, indent=4, sort_keys=True)
