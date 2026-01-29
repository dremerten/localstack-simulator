#!/bin/bash
set -euo pipefail

export HISTFILE=/workspace/.bash_history
export PATH=/usr/bin:/bin:/opt/allowed-bin

if [ -d /workspace ]; then
  rm -rf /workspace/ansible /workspace/terraform /workspace/pulumi /workspace/Makefile /workspace/README.md
  cp -R /opt/seed/workspace/. /workspace/
  touch /workspace/.seeded
fi

mkdir -p /workspace/.terraform.d/plugin-cache
mkdir -p /workspace/.terraform-bin
mkdir -p /workspace/.ansible/tmp
mkdir -p /workspace/.pulumi/plugins
mkdir -p /workspace/.pulumi-cli
mkdir -p /workspace/.aws-cli-bin

if [ -f /opt/aws-cli-cache/awscliv2.zip ] && [ ! -x /workspace/.aws-cli-bin/aws ]; then
  rm -rf /workspace/.aws-cli /workspace/.aws-cli-bin /workspace/.aws-cli-src
  mkdir -p /workspace/.aws-cli-src
  unzip -q /opt/aws-cli-cache/awscliv2.zip -d /workspace/.aws-cli-src
  /workspace/.aws-cli-src/aws/install --bin-dir /workspace/.aws-cli-bin --install-dir /workspace/.aws-cli --update
  rm -rf /workspace/.aws-cli-src
fi

if [ -f /opt/terraform-cache/terraform.zip ] && [ ! -x /workspace/.terraform-bin/terraform ]; then
  unzip -q -o /opt/terraform-cache/terraform.zip -d /workspace/.terraform-bin
  chmod +x /workspace/.terraform-bin/terraform
fi

pulumi_version=""
if [ -f /opt/pulumi-cache/pulumi.version ]; then
  pulumi_version="$(cat /opt/pulumi-cache/pulumi.version)"
fi
workspace_pulumi_version=""
if [ -f /workspace/.pulumi-cli/.version ]; then
  workspace_pulumi_version="$(cat /workspace/.pulumi-cli/.version)"
fi
if [ -f /opt/pulumi-cache/pulumi.tgz ] && [ "${pulumi_version}" != "${workspace_pulumi_version}" ]; then
  rm -rf /workspace/.pulumi-cli
  mkdir -p /workspace/.pulumi-cli
  tar -xzf /opt/pulumi-cache/pulumi.tgz -C /workspace/.pulumi-cli --strip-components=1
  printf '%s' "${pulumi_version}" > /workspace/.pulumi-cli/.version
fi

if [ -f /opt/pulumi-plugins-cache/aws.tgz ]; then
  if ! ls /workspace/.pulumi/plugins/*/pulumi-resource-aws >/dev/null 2>&1; then
    tar -xzf /opt/pulumi-plugins-cache/aws.tgz -C /workspace/.pulumi/plugins
  fi
fi

if [ -f /opt/terraform-plugins-cache/terraform-provider-aws.zip ] && [ -f /opt/terraform-plugins-cache/aws.version ]; then
  tf_version="$(cat /opt/terraform-plugins-cache/aws.version)"
  case "$(uname -m)" in
    x86_64) tf_arch=amd64 ;;
    aarch64|arm64) tf_arch=arm64 ;;
    *) tf_arch=amd64 ;;
  esac
  tf_dir="/workspace/.terraform.d/plugin-cache/registry.terraform.io/hashicorp/aws/${tf_version}/linux_${tf_arch}"
  if ! ls "${tf_dir}"/terraform-provider-aws_* >/dev/null 2>&1; then
    mkdir -p "${tf_dir}"
    unzip -q -o /opt/terraform-plugins-cache/terraform-provider-aws.zip -d "${tf_dir}"
    chmod +x "${tf_dir}"/terraform-provider-aws_*
  fi
fi
if [ -f /opt/seed/workspace/ansible/ansible.cfg ]; then
  mkdir -p /workspace/ansible
  cp -f /opt/seed/workspace/ansible/ansible.cfg /workspace/ansible/ansible.cfg
fi
if [ -f /opt/seed/workspace/Makefile ] && [ ! -f /workspace/Makefile ]; then
  cp -f /opt/seed/workspace/Makefile /workspace/Makefile
fi
if [ -f /opt/seed/workspace/terraform/.terraformrc ]; then
  mkdir -p /workspace/terraform
  cp -f /opt/seed/workspace/terraform/.terraformrc /workspace/terraform/.terraformrc
fi

cd /home/sandbox/workspace

exec /usr/local/bin/ttyd -p "${PORT}" -W /bin/bash -l
