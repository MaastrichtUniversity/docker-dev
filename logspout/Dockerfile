FROM gliderlabs/logspout:master
ENV SYSLOG_FORMAT rfc3164
ADD ./bootstrap.sh /bin/bootstrap.sh
RUN chmod a+x /bin/bootstrap.sh


ENTRYPOINT ["/bin/bootstrap.sh"]