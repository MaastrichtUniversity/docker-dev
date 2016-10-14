FROM metalnx/metalnx-web:1.0-latest

ADD ./templates.sql /tmp/templates.sql
ADD ./template_fields.sql /tmp/template_fields.sql


ADD ./supervisord.conf /etc/supervisord.conf
ADD ./start_metalnx.sh /start_metalnx.sh

EXPOSE 8080

CMD ["/bin/bash", "/start_metalnx.sh"]