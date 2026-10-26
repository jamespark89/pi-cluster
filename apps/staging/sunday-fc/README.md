# Sunday FC

The app (`ghcr.io/jamespark89/sunday-fc-app`), its Postgres database, nightly
backups, and a Cloudflare Tunnel for https://sundayfc.jamespark.dev.

Secrets aren't stored in git. Create them once, before the first sync:

```sh
kubectl create namespace sunday-fc

# 1. Database password
kubectl -n sunday-fc create secret generic sunday-fc-db \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=')"

# 2. App settings: copy the app's .env.example to prod.env, fill it in, then:
#    DATABASE_URL=postgresql://postgres:<the password above>@sunday-fc-db:5432/sundayfc?schema=public
#    NEXTAUTH_URL=https://sundayfc.jamespark.dev
kubectl -n sunday-fc create secret generic sunday-fc-env --from-env-file=prod.env
rm prod.env

# 3. Cloudflare Tunnel
cloudflared tunnel create sundayfc
cloudflared tunnel route dns sundayfc sundayfc.jamespark.dev
kubectl -n sunday-fc create secret generic tunnel-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/<tunnel-id>.json

# 4. Only while the image is private: a GitHub token with read:packages
kubectl -n sunday-fc create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=jamespark89 --docker-password=<token>
```

To change a setting: edit prod.env, re-create `sunday-fc-env` (delete it, then
create it again), then `kubectl -n sunday-fc rollout restart deployment/sunday-fc`.

## Releasing

Pushing to the app's `main` builds `ghcr.io/jamespark89/sunday-fc-app:sha-<commit>`.
Set that tag as `newTag` in `kustomization.yaml` and push; Flux deploys it, and
the `migrate` init container applies any new database migrations first.

## Backups and restore

`sunday-fc-db-backup` dumps the database at 3am every night into the
`sunday-fc-backups` volume, keeping 14 days. The volumes use local-path
storage on the node, so also copy dumps off the machine now and then:

```sh
pod=$(kubectl -n sunday-fc get pod -l app=sunday-fc-db -o name)
kubectl -n sunday-fc exec $pod -- pg_dump -U postgres sundayfc | gzip > sundayfc-$(date +%F).sql.gz
```

Restore (replaces everything):

```sh
gunzip -c sundayfc-<date>.sql.gz | kubectl -n sunday-fc exec -i $pod -- psql -U postgres -d sundayfc
```

Careful: deleting this folder from git makes Flux delete the namespace, and
local-path deletes volume data with it.
