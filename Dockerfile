# syntax=docker/dockerfile:1.7
ARG DEBIAN_VERSION=bookworm-slim
ARG PYTHON_VERSION=3.14.2
ARG PULUMI_VERSION=3.217.1
ARG PULUMI_AWS_VERSION=7.16.0

FROM debian:${DEBIAN_VERSION} AS fetch
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl unzip binutils \
  && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
ARG TERRAFORM_VERSION=1.14.3
ARG AWS_PROVIDER_VERSION=5.0.0
RUN set -eu; \
  case "${TARGETARCH:-amd64}" in \
    amd64) tf_arch=amd64 ;; \
    arm64) tf_arch=arm64 ;; \
    *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
  esac; \
  curl -fsSLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${tf_arch}.zip"; \
  mkdir -p /opt/terraform-cache; \
  mv /tmp/terraform.zip /opt/terraform-cache/terraform.zip; \
  printf '%s\n' "${TERRAFORM_VERSION}" > /opt/terraform-cache/terraform.version
RUN set -eu; \
  case "${TARGETARCH:-amd64}" in \
    amd64) tf_arch=amd64 ;; \
    arm64) tf_arch=arm64 ;; \
    *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
  esac; \
  curl -fsSLo /tmp/aws-provider.zip "https://releases.hashicorp.com/terraform-provider-aws/${AWS_PROVIDER_VERSION}/terraform-provider-aws_${AWS_PROVIDER_VERSION}_linux_${tf_arch}.zip"; \
  mkdir -p /opt/terraform-plugins-cache; \
  mv /tmp/aws-provider.zip /opt/terraform-plugins-cache/terraform-provider-aws.zip; \
  printf '%s\n' "${AWS_PROVIDER_VERSION}" > /opt/terraform-plugins-cache/aws.version

ARG TTYD_VERSION=1.7.7
RUN set -eu; \
  case "${TARGETARCH:-amd64}" in \
    amd64) ttyd_arch=x86_64 ;; \
    arm64) ttyd_arch=aarch64 ;; \
    *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
  esac; \
  curl -fsSLo /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${ttyd_arch}"; \
  chmod +x /usr/local/bin/ttyd; \
  strip /usr/local/bin/ttyd

RUN set -eu; \
  case "${TARGETARCH:-amd64}" in \
    amd64) aws_arch=x86_64 ;; \
    arm64) aws_arch=aarch64 ;; \
    *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
  esac; \
  mkdir -p /opt/aws-cli-cache; \
  curl -fsSLo /opt/aws-cli-cache/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip"

ARG PULUMI_VERSION
ARG PULUMI_AWS_VERSION
RUN set -eu; \
  case "${TARGETARCH:-amd64}" in \
    amd64) pulumi_arch=x64 ;; \
    arm64) pulumi_arch=arm64 ;; \
    *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
  esac; \
  curl -fsSLo /tmp/pulumi.tgz "https://get.pulumi.com/releases/sdk/pulumi-v${PULUMI_VERSION}-linux-${pulumi_arch}.tar.gz"; \
  mkdir -p /tmp/pulumi-dist /opt/pulumi-cache /opt/pulumi-plugins-cache; \
  tar -C /tmp/pulumi-dist -xzf /tmp/pulumi.tgz; \
  find /tmp/pulumi-dist/pulumi -maxdepth 1 -type f -name 'pulumi-language-*' ! -name 'pulumi-language-python' ! -name 'pulumi-language-python-exec' -delete; \
  strip /tmp/pulumi-dist/pulumi/pulumi /tmp/pulumi-dist/pulumi/pulumi-language-python; \
  strip /tmp/pulumi-dist/pulumi/pulumi-language-python-exec || true; \
  tar -C /tmp/pulumi-dist -czf /opt/pulumi-cache/pulumi.tgz pulumi; \
  printf '%s\n' "${PULUMI_VERSION}" > /opt/pulumi-cache/pulumi.version; \
  PULUMI_HOME=/tmp/pulumi-home /tmp/pulumi-dist/pulumi/pulumi plugin install resource aws "${PULUMI_AWS_VERSION}"; \
  if [ -d /tmp/pulumi-home/plugins ]; then \
    for f in /tmp/pulumi-home/plugins/*/pulumi-resource-*; do strip "$f" || true; done; \
    tar -C /tmp/pulumi-home/plugins -czf /opt/pulumi-plugins-cache/aws.tgz .; \
  fi; \
  printf '%s\n' "${PULUMI_AWS_VERSION}" > /opt/pulumi-plugins-cache/aws.version

FROM python:${PYTHON_VERSION}-slim AS python-build
ARG PULUMI_VERSION
ARG PULUMI_AWS_VERSION
RUN apt-get update \
  && apt-get install -y --no-install-recommends gcc libffi-dev libssl-dev \
  && rm -rf /var/lib/apt/lists/*
RUN python -m venv /opt/venv
RUN /opt/venv/bin/pip install --no-cache-dir --no-compile ansible-core==2.20.1 pulumi==${PULUMI_VERSION} pulumi-aws==${PULUMI_AWS_VERSION} \
  && find /opt/venv -type d -name __pycache__ -prune -exec rm -rf {} + \
  && find /opt/venv -type f -name '*.pyc' -delete

FROM python:${PYTHON_VERSION}-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends bash ca-certificates coreutils make tar unzip vim openssl libssl3t64 \
  && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/locale

COPY --from=fetch /opt/terraform-cache /opt/terraform-cache
COPY --from=fetch /usr/local/bin/ttyd /usr/local/bin/ttyd
COPY --from=fetch /opt/aws-cli-cache /opt/aws-cli-cache
COPY --from=fetch /opt/terraform-plugins-cache /opt/terraform-plugins-cache
COPY --from=fetch /opt/pulumi-cache /opt/pulumi-cache
COPY --from=fetch /opt/pulumi-plugins-cache /opt/pulumi-plugins-cache
COPY --from=python-build /opt/venv /opt/venv
COPY docker/allowed-bin/ /opt/allowed-bin/
COPY docker/ui/ /opt/ui/

ENV PATH=/opt/allowed-bin \
    PORT=5446 \
    HOME=/home/sandbox

RUN printf '%s\n' 'export PATH=/opt/allowed-bin' 'readonly PATH' 'umask 077' > /etc/profile.d/sandbox-path.sh
RUN printf '%s\n' \
  'cd() {' \
  '  local target="${1:-$HOME}"' \
  '  local target_path resolved' \
  '  if [ "$target" = "-" ]; then target="${OLDPWD:-$PWD}"; fi' \
  '  if [ "${target#/}" != "$target" ]; then' \
  '    target_path="$target"' \
  '  else' \
  '    target_path="$PWD/$target"' \
  '  fi' \
  '  resolved="$(command cd -- "$target_path" 2>/dev/null && pwd -P)" || { echo "cd: $target: No such file or directory" >&2; return 1; }' \
  '  case "$resolved" in' \
  '    /workspace|/workspace/*|/home/sandbox|/home/sandbox/*) builtin cd "$resolved" ;;' \
  '    *) echo "cd: access denied" >&2; return 1 ;;' \
  '  esac' \
  '}' > /etc/profile.d/sandbox-cd.sh
RUN printf '%s\n' \
  'case "$-" in *i*) ;; *) return 0 ;; esac' \
  'if [ -d /workspace ] && [ -d /opt/seed/workspace ]; then' \
  '  /bin/rm -rf /workspace/ansible /workspace/terraform /workspace/pulumi /workspace/Makefile /workspace/README.md' \
  '  /bin/cp -R /opt/seed/workspace/. /workspace/' \
  'fi' > /etc/profile.d/sandbox-reset.sh
RUN printf '%s\n' \
  'provider_installation {' \
  '  filesystem_mirror {' \
  '    path    = "/workspace/.terraform.d/plugin-cache"' \
  '    include = ["hashicorp/aws"]' \
  '  }' \
  '  direct {' \
  '    exclude = ["hashicorp/aws"]' \
  '  }' \
  '}' > /opt/terraformrc

RUN /usr/bin/ln -s /bin/bash /usr/local/bin/rbash \
  && /usr/bin/chmod 0711 / /etc \
  && /usr/bin/chmod -R 0555 /opt/allowed-bin

RUN /usr/sbin/useradd -m -u 1000 -s /bin/bash sandbox \
  && /usr/bin/mkdir -p /workspace /home/sandbox \
  && /usr/bin/ln -s /workspace /home/sandbox/workspace \
  && /usr/bin/ln -s /workspace/.ansible /home/sandbox/.ansible \
  && /usr/bin/ln -s /opt/terraformrc /home/sandbox/.terraformrc \
  && /usr/bin/chown -R sandbox:sandbox /workspace /home/sandbox

COPY docker/seed/ /opt/seed/

RUN /usr/bin/find / -xdev \( -path /proc -o -path /sys -o -path /dev \) -prune -o -perm /6000 -type f -exec /usr/bin/chmod a-s {} + \
  && /usr/bin/rm -f /opt/venv/bin/pip /opt/venv/bin/pip3 /opt/venv/bin/pip3.* || true

COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh

USER 1000:1000
WORKDIR /home/sandbox/workspace
EXPOSE 5446
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
