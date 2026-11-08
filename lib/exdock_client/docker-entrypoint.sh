#!/bin/sh
set -eu

docker_socket=/var/run/docker.sock
run_as=nonroot:nonroot

if [ -S "$docker_socket" ]; then
  socket_gid="$(stat -c '%g' "$docker_socket")"
  socket_group="$(awk -F: -v gid="$socket_gid" '$3 == gid { print $1; exit }' /etc/group)"

  if [ -z "$socket_group" ]; then
    socket_group=docker_socket
    addgroup -S -g "$socket_gid" "$socket_group"
  fi

  run_as="nonroot:$socket_group"
fi

exec su-exec "$run_as" "$@"
