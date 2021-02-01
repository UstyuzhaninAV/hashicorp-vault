FROM golang:1.13.3-stretch AS build


WORKDIR /go/src/github.com/hashicorp/vault

RUN \
  curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
  echo 'deb http://deb.nodesource.com/node_12.x stretch main' > /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && apt-get install -y \
  nodejs \
  bzip2 \
  zip \
  xz-utils && \
  npm install yarn@1.10.1 -g

ENV VAULT_TAG v1.2.3

RUN git clone https://github.com/hashicorp/vault.git . && \
    git checkout "${VAULT_TAG}" && \
    make bootstrap

# built vault and ui to have efficient docker layer caching
RUN make ember-dist static-assets bin XC_OSARCH=linux/amd64

COPY patches /tmp/patches

RUN git config --global user.email "ustiuzhanin@exbico.com" && git config --global user.name "Anton Ustiuzhanin"


# patch UI
RUN \
  git am /tmp/patches/0002-Implement-google-oauth2-in-the-UI.patch && \
  git am /tmp/patches/0003-Disable-UI-auth-backends-apart-from-token-and-google.patch

# build UI
RUN \
  make ember-dist static-assets

# built in plugin into vault
RUN git am /tmp/patches/0001-Integrate-Google-G-Suite-credentials-plugin.patch
COPY ./vault-plugin-auth-google/vendor/google.golang.org/api/admin/directory/v1/*.go ./vendor/google.golang.org/api/admin/directory/v1/
COPY ./vault-plugin-auth-google/google/*.go ./vendor/github.com/jetstack/vault-plugin-auth-google/google/

# rebuilt vault
RUN \
  sed -i "s/VersionPrerelease =.*/VersionPrerelease = \"jetstack1\"/g" version/version_base.go && \
  make bin XC_OSARCH=linux/amd64

FROM alpine:3.10.3

# Create a vault user and group first so the IDs get set the same way,
# even as the rest of this may change over time.
RUN addgroup vault && \
    adduser -S -G vault vault

# Install required packages
RUN apk add --no-cache ca-certificates libcap su-exec dumb-init

# Copy build over
COPY --from=build /go/src/github.com/hashicorp/vault/bin/vault /bin/vault

# /vault/logs is made available to use as a location to store audit logs, if
# desired; /vault/file is made available to use as a location with the file
# storage backend, if desired; the server will be started with /vault/config as
# the configuration directory so you can add additional config files in that
# location.
RUN mkdir -p /vault/logs && \
    mkdir -p /vault/file && \
    mkdir -p /vault/config && \
    chown -R vault:vault /vault

# Expose the logs directory as a volume since there's potentially long-running
# state in there
VOLUME /vault/logs

# Expose the file directory as a volume since there's potentially long-running
# state in there
VOLUME /vault/file

# 8200/tcp is the primary interface that applications use to interact with
# Vault.
EXPOSE 8200

# The entry point script uses dumb-init as the top-level process to reap any
# zombie processes created by Vault sub-processes.
#
# For production derivatives of this container, you shoud add the IPC_LOCK
# capability so that Vault can mlock memory.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

# By default you'll get a single-node development server that stores everything
# in RAM and bootstraps itself. Don't use this configuration for production.
CMD ["server", "-dev"]
