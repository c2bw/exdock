# Backup and recovery

Run these commands from the installation directory. Use the same Compose project
name, environment file, and override files as your deployment. The examples use
project `exdock` and `.env`.

Set the Compose file for your installation:

```sh
compose_file=compose.release.yml
# For a source-built installation instead:
# compose_file=compose.quickstart.yml
```

## Back up

This procedure pauses Exdock so the database and any SQLite sidecar files can be
copied together. It does not stop your managed workloads. Run it before an
upgrade or restore, and keep each backup in its own directory.

```sh
umask 077
mkdir -p backups
backup_dir="backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$backup_dir"
docker compose -p exdock --env-file .env -f "$compose_file" stop

docker compose -p exdock --env-file .env -f "$compose_file" \
  run --rm -T --no-deps --entrypoint sh server \
  -c 'tar -czf - -C /data/db .' > "$backup_dir/database.tar.gz"
cp .env "$backup_dir/server.env"
cp "$compose_file" "$backup_dir/compose.yml"
docker compose -p exdock --env-file .env -f "$compose_file" config --images > "$backup_dir/images.txt"
tar -tzf "$backup_dir/database.tar.gz"

docker compose -p exdock --env-file .env -f "$compose_file" up -d
```

For source-built installations, also save the build revision with
`git rev-parse HEAD > "$backup_dir/source-revision.txt"` from the original
checkout before changing revisions.

Only retain a backup as successful if the archive command and listing succeed.
If a command fails, resolve it before upgrading; start Exdock again if needed.
Include any custom Compose overrides in your secure backup. Backups contain
credentials and sensitive configuration: restrict access and copy them to
separate protected storage. The database archive and its matching
`DB_VAULT_KEY` are both required for recovery. Exdock backups do not include
application volumes or data belonging to managed containers.

## Restore into a separate volume

Use the saved image versions and configuration. For source-built images, also
record and restore the source commit used to build them. Stop the original Exdock
installation first, especially its agent, so the restored instance does not
compete for the same node identity. The example below uses project
`exdock-restored`, which creates a separate volume and preserves the original.

```sh
# Replace this with the directory for the backup you selected.
backup_dir=backups/YOUR_BACKUP_DIRECTORY
cp "$backup_dir/server.env" .env.restore
cp "$backup_dir/compose.yml" compose.restore.yml
chmod 600 .env.restore

# Published images: retrieve the matching pair before restoring.
docker compose -p exdock-restored --env-file .env.restore -f compose.restore.yml pull
# For a source-built backup, use its original checkout and run build instead.

docker compose -p exdock-restored --env-file .env.restore -f compose.restore.yml \
  run --rm -T --no-deps --entrypoint sh server \
  -c 'test ! -e /data/db/exdock.db && tar -xzf - -C /data/db' \
  < "$backup_dir/database.tar.gz"

docker compose -p exdock-restored --env-file .env.restore -f compose.restore.yml up -d
```

The restore refuses to overwrite an existing database. Keep using project
`exdock-restored` and `.env.restore` for its future commands and backups. Verify
login, saved settings, connected nodes, and container inventory before retiring
the original installation. Restore any private-network/proxy overrides you use.
Do not remove the original volume until the restored installation is verified.

