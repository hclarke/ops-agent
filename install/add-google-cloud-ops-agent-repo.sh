#!/bin/bash
# Copyright 2020 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Add repository for the Google ops agent.
#
# This script configures the required apt or yum repository.
# The environment variable REPO_SUFFIX can be set to alter which repository is
# used. A dash (-) will be inserted prior to the supplied suffix. An example
# value is '0' that contains all 0.*.* agent versions. <REPO_SUFFIX> defaults
# to 'all' which contains all agent versions across different major versions.
# The full repository name is:
# "google-cloud-ops-agent-<DISTRO>[-<ARCH>]-<REPO_SUFFIX>".
#
# Sample usage:
# 1. To add the repo that contains all agent versions, run:
#     $ bash add-google-cloud-ops-agent-repo.sh
# 2. To add the repo and also install the latest agent, run:
#     $ bash add-google-cloud-ops-agent-repo.sh --also-install
# 3. To run the script with verbose logging, run:
#     $ bash add-google-cloud-ops-agent-repo.sh --also-install --verbose
# 4. To add a specific repo by REPO_SUFFIX.
#     For instance, to add the repo that only include 0.*.* versions of the agent to
#     avoid accidentally pulling in a new major version with breaking change, run:
#     $ REPO_SUFFIX=0 bash add-google-cloud-ops-agent-repo.sh

# Parsing flag value.
OPTS="$(getopt -o vhns: --long also-install --long verbose -n 'add-google-cloud-ops-agent-repo' -- "$@")"

# Fail the script if parsing goes wrong.
if [[ $? != 0 ]]; then echo "Failed parsing options." >&2 ; exit 1 ; fi

echo "$OPTS"
eval set -- "$OPTS"

while true; do
  case "$1" in
    --also-install)
      INSTALL="true"; shift ;;
    --verbose)
      VERBOSE="true"; shift ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

if [[ "$VERBOSE" = 'true' ]]; then
  echo "Enable verbose logging."
  set -x
fi

# Host that serves the repositories.
REPO_HOST='packages.cloud.google.com'

# URL for the ops agent documentation.
OPS_AGENT_DOCS_URL="https://cloud.google.com/stackdriver/docs/solutions/ops-agent"

# URL documentation which lists supported platforms for running the ops agent.
OPS_AGENT_SUPPORTED_URL="${OPS_AGENT_DOCS_URL}/#supported_operating_systems"

# Package Name.
OPS_AGENT_NAME="google-cloud-ops-agent"

# <REPO_SUFFIX> defaults to 'all'.
[[ -z "${REPO_SUFFIX-}" ]] && REPO_SUFFIX='all'

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
fi

handle_debian() {
  lsb_release -v >/dev/null 2>&1 || { \
    apt-get update; apt-get -y install lsb-release; \
  }
  apt-get update; apt-get -y install apt-transport-https ca-certificates
  local CODENAME="$(lsb_release -sc)"
  local REPO_NAME="google-cloud-ops-agent-${CODENAME}${REPO_SUFFIX+-${REPO_SUFFIX}}"
  cat > /etc/apt/sources.list.d/google-cloud-ops-agent.list <<EOM
deb https://${REPO_HOST}/apt ${REPO_NAME} main
EOM
  curl --connect-timeout 5 -s -f "https://${REPO_HOST}/apt/doc/apt-key.gpg" | apt-key add -
  install_agent() {
    apt-get update || { \
      echo "Could not update apt repositories."; \
      echo "Please check your network connectivity and"; \
      echo "make sure you are running a supported Ubuntu/Debian distribution."; \
      echo "See ${OPS_AGENT_SUPPORTED_URL} for a list of supported platforms."; \
    }
    # apt-get (https://linux.die.net/man/8/apt-get) does not have a verbose
    # flag. So we use the same command regardless.
    apt-get -y install "$OPS_AGENT_NAME"
  }
}

# Takes the repo codename as a parameter.
handle_rpm() {
  lsb_release -v >/dev/null 2>&1 || yum -y install redhat-lsb-core
  local REPO_NAME="google-cloud-ops-agent-${1}-\$basearch${REPO_SUFFIX+-${REPO_SUFFIX}}"
  cat > /etc/yum.repos.d/google-cloud-ops-agent.repo <<EOM
[google-cloud-ops-agent]
name=Google Cloud Ops Agent Repository
baseurl=https://${REPO_HOST}/yum/repos/${REPO_NAME}
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://${REPO_HOST}/yum/doc/yum-key.gpg
       https://${REPO_HOST}/yum/doc/rpm-package-key.gpg
EOM
  install_agent() {
    yum list updates -y || { \
      echo "Could not refresh the google-cloud-ops-agent yum repositories."; \
      echo "Please check your network connectivity and"; \
      echo "make sure you are running a supported CentOS/RHEL distribution."; \
      echo "See ${OPS_AGENT_SUPPORTED_URL} for a list of supported platforms."; \
    }
    if [[ "$VERBOSE" = 'true' ]]; then
      yum -y -v install "$OPS_AGENT_NAME"
    else
      yum -y install "$OPS_AGENT_NAME"
    fi
  }
}

handle_redhat() {
  local VERSION_PRINTER='import platform; print(platform.dist()[1].split(".")[0])'
  local MAJOR_VERSION="$(python2 -c "${VERSION_PRINTER}")"
  handle_rpm "el${MAJOR_VERSION}"
}

handle_suse() {
  SUSE_VERSION=${VERSION%%-*}
  local REPO_NAME="google-cloud-ops-agent-sles${SUSE_VERSION}-\$basearch${REPO_SUFFIX+-${REPO_SUFFIX}}"
  # TODO: expand all short arguments in this script, for readability.
  zypper -n refresh || { \
    echo "Could not refresh zypper repositories."; \
    echo "This is not necessarily a fatal error; proceeding..."; \
  }
  zypper addrepo -g -t YUM "https://${REPO_HOST}/yum/repos/${REPO_NAME}" google-cloud-ops-agent
  rpm --import "https://${REPO_HOST}/yum/doc/yum-key.gpg" "https://${REPO_HOST}/yum/doc/rpm-package-key.gpg"
  install_agent() {
    zypper -n refresh google-cloud-ops-agent || { \
      echo "Could not refresh the google-cloud-ops-agent zypper repositories."; \
      echo "Please check your network connectivity and"; \
      echo "make sure you are running a supported SUSE distribution."; \
      echo "See ${OPS_AGENT_SUPPORTED_URL} for a list of supported platforms."; \
      exit 1; \
    }
    zypper -n install "$OPS_AGENT_NAME"
    if [[ "$VERBOSE" = 'true' ]]; then
      zypper -n -vv install "$OPS_AGENT_NAME"
    else
      zypper -n install "$OPS_AGENT_NAME"
    fi
  }
}

case "${ID:-}" in
  debian|ubuntu)
    echo 'Adding agent repository for Debian or Ubuntu.'
    handle_debian
    ;;
  rhel|centos)
    echo 'Adding agent repository for RHEL or CentOS.'
    handle_redhat
    ;;
  sles)
    echo 'Adding agent repository for SLES.'
    handle_suse
    ;;
  *)
    # Fallback for systems lacking /etc/os-release.
    if [[ -f /etc/debian_version ]]; then
      echo 'Adding agent repository for Debian.'
      handle_debian
    elif [[ -f /etc/redhat-release ]]; then
      echo 'Adding agent repository for Red Hat.'
      handle_redhat
    elif [[ -f /etc/SuSE-release ]]; then
      echo 'Adding agent repository for SLES.'
      handle_suse
    else
      echo >&2 'Unidentifiable or unsupported platform.'
      echo >&2 "See ${OPS_AGENT_SUPPORTED_URL} for a list of supported platforms."
      exit 1
    fi
esac

if [[ "$INSTALL" = 'true' ]]; then
  if ! install_agent; then
    echo "$OPS_AGENT_NAME installation failed."
  else
    echo "$OPS_AGENT_NAME installation succeeded."
  fi
fi
