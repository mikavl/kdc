FROM library/debian:bullseye-slim

RUN apt-get update \
 && apt-get install --assume-yes --no-install-recommends \
      krb5-admin-server \
      krb5-kdc \
      krb5-kpropd \
 && rm -rf /var/lib/apt/lists/*
