FROM library/debian:bullseye-slim

COPY --chown=root:root usr /usr/

RUN apt-get update \
 && apt-get install --assume-yes --no-install-recommends \
      krb5-admin-server \
      krb5-kdc \
      krb5-kpropd \
 && rm -rf /var/lib/apt/lists/* \
    \
 && chmod 0755 /usr/local/bin/* \
    \
 && rm -rf /etc/krb5kdc /var/lib/krb5kdc \
 && install -d -m 0700 -o root -g root \
      /etc/krb5kdc \
      /var/lib/krb5kdc

COPY --chown=root:root etc /etc/
