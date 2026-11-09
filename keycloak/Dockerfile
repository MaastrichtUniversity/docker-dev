FROM quay.io/keycloak/keycloak:15.0.2

USER root
RUN microdnf update -y && microdnf install -y jq

# /dh_is_ready.sh will print if container is ready for us or not
# (hacky and cheap "orchestration")
ADD ./dh_is_ready.sh /dh_is_ready.sh

# Baked in for k8s (docker compose bind-mounted these instead):
# import.sh/startup.sh run on startup, realm/users are imported by import.sh.
ADD ./realm-export.json /tmp/realm-export.json
ADD ./users.json /tmp/users.json
ADD ./import.sh /tmp/import.sh
RUN chmod +x /tmp/import.sh
COPY ./startup.sh /opt/jboss/startup-scripts/startup.sh
RUN chmod +x /opt/jboss/startup-scripts/startup.sh
COPY ./datahub-keycloak-theme /opt/jboss/keycloak/themes/datahub


# Entry point: jboss/keycloak will call scripts under /opt/jboss/startup-scripts/
