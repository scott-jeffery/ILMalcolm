#!/bin/bash

SCRIPT_PATH="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
unset SSH_AUTH_SOCK

function vm_state() {
  vagrant status --machine-readable | grep ",state," | egrep -o '([a-z_]*)$'
}

function vm_is_running() {
  STATE="$(vm_state)"
  if [[ "$STATE" == "running" ]] ; then
    return 0
  else
    return 1
  fi
}

function vm_execute() {
  echo "Running $1" >&2
  vagrant ssh --no-tty --command "$1"
}

unset FORCE_PROVISION
XZ_EXT=
IMAGE=raspi_4_bookworm.img
while getopts 'fi:z' OPTION; do
  case "$OPTION" in
    f)
      FORCE_PROVISION=0
      ;;

    i)
      IMAGE=${OPTARG}
      ;;

    z)
      XZ_EXT=.xz
      ;;

    ?)
      echo "script usage: $(basename $0) [-f]" >&2
      exit 1
      ;;
  esac
done
shift "$(($OPTIND -1))"


function cleanup_shared_and_docs {
  # clean up temporary files
  rm -rf "$SCRIPT_PATH"/shared \
         "$SCRIPT_PATH"/.fuse_hidden*
  # if we created an .xz, delete the original .img
  if [[ -f "$SCRIPT_PATH/$IMAGE" ]] && [[ -n "$XZ_EXT" ]] && [[ -f "$SCRIPT_PATH/$IMAGE$XZ_EXT" ]] ; then
    rm -f "$SCRIPT_PATH/$IMAGE"
  fi
}


pushd "$SCRIPT_PATH"/ >/dev/null 2>&1
make clean >/dev/null 2>&1
popd >/dev/null 2>&1

pushd "$SCRIPT_PATH"/vagrant

VM_NAME="$(grep "config.vm.box" Vagrantfile | tr -d "[:space:]" | sed "s/.*=//")"

if [[ -n $FORCE_PROVISION ]]; then
  echo "Destroying build machine to force provisioning..." >&2
  vagrant destroy -f
  sleep 1
fi

# make sure the VM is up and running, or start it otherwise
if ! vm_is_running; then
  echo "Starting build machine..." >&2
  vagrant up
  NEED_SHUTDOWN=true
  sleep 1
fi
until vm_is_running; do
  echo "Waiting for $VM_NAME..." >&2
  sleep 1
done
echo "$VM_NAME is running!" >&2

# make sure we can connect via SSH
echo "Checking SSH availability..." >&2
until vm_execute 'sudo whoami' | grep -q "root" ; do
  echo "Waiting for SSH availability..." >&2
  sleep 1
done
echo "SSH available." >&2

cleanup_shared_and_docs
mkdir "$SCRIPT_PATH"/shared
YML_IMAGE_VERSION="$(grep -P "^\s+image:.*/malcolm/" "$SCRIPT_PATH"/../docker-compose.yml | awk '{print $2}' | cut -d':' -f2 | uniq -c | sort -nr | awk '{print $2}' | head -n 1)"
[[ -n $YML_IMAGE_VERSION ]] && echo "$YML_IMAGE_VERSION" > "$SCRIPT_PATH"/shared/version.txt
[[ ${#MAXMIND_GEOIP_DB_LICENSE_KEY} -gt 1 ]] && echo "$MAXMIND_GEOIP_DB_LICENSE_KEY" > "$SCRIPT_PATH"/shared/maxmind_license.txt
[[ ${#MAXMIND_GEOIP_DB_ALTERNATE_DOWNLOAD_URL} -gt 1 ]] && echo "$MAXMIND_GEOIP_DB_ALTERNATE_DOWNLOAD_URL" > "$SCRIPT_PATH"/shared/maxmind_url.txt
[[ ${#GITHUB_TOKEN} -gt 1 ]] && echo "GITHUB_TOKEN=$GITHUB_TOKEN" >> "$SCRIPT_PATH"/shared/environment.chroot
echo "VCS_REVSION=$( git rev-parse --short HEAD 2>/dev/null || echo main )" >> "$SCRIPT_PATH"/shared/environment.chroot
trap cleanup_shared_and_docs EXIT

vm_execute "sudo bash -c \"whoami && cd /Malcolm/hedgehog-raspi && pwd && make ${IMAGE}${XZ_EXT}\""

if [[ -n $NEED_SHUTDOWN ]]; then
  echo "Shutting down $VM_NAME..." >&2
  vagrant halt
  sleep 1
  while vm_is_running; do
    echo "Waiting for $VM_NAME to shutdown..." >&2
    sleep 1
  done
  echo "$VM_NAME is stopped." >&2
fi

popd
