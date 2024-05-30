FROM quay.io/keycloak/keycloak:15.0.2

USER root
RUN microdnf update -y && microdnf install -y jq

# /dh_is_ready.sh will print if container is ready for us or not
# (hacky and cheap "orchestration")
ADD ./dh_is_ready.sh /dh_is_ready.sh


# Entry point: jboss/keycloak will call scripts under /opt/jboss/startup-scripts/
