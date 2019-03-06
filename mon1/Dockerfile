ARG CEPH_CONTAINER_VERSION

FROM ceph/daemon:${CEPH_CONTAINER_VERSION}

ARG VOLUMES_PATH
ARG DISKS_PATH
ARG DASHBOARD_PORT
ARG RGW_PORT
ARG CEPH_PUBLIC_NETWORK
ARG MON_IP

RUN zypper --non-interactive install \
	tar \
	curl \
	netcat

RUN mkdir /opt/ceph
ADD bootstrap.sh /opt/ceph/bootstrap.sh
ENTRYPOINT /opt/ceph/bootstrap.sh
