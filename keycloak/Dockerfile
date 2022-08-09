FROM jboss/keycloak:15.0.2

USER root
RUN microdnf update -y && microdnf install -y jq

ADD check_health.sh /opt

HEALTHCHECK --interval=45s --timeout=10s --start-period=20s CMD /opt/check_health.sh
