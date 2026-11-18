# Home Stock

The household inventory app (`ghcr.io/jamespark89/home-stock`), its Postgres
database, nightly backups, and a Cloudflare Tunnel for
https://homestock.jamespark.dev.

**Before pushing this folder:** Flux deploys everything under `apps/staging`,
so the image must exist and `newTag` in `kustomization.yaml` must point at it,
and the secrets below must be created first.

Secrets aren't stored in git. Create them once, before the first sync, with
`bash create-secrets.sh` (the tunnel already exists), or by hand:

```sh
kubectl create namespace home-stock

# 1. Database password
kubectl -n home-stock create secret generic home-stock-db \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=')"

# 2. App settings: copy the app's .env.example to prod.env, fill it in, then:
#    DATABASE_URL=postgresql://postgres:<the password above>@home-stock-db:5432/homestock?schema=public
kubectl -n home-stock create secret generic home-stock-env --from-env-file=prod.env
rm prod.env

# 3. Cloudflare Tunnel
cloudflared tunnel create homestock
cloudflared tunnel route dns homestock homestock.jamespark.dev
kubectl -n home-stock create secret generic tunnel-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/<tunnel-id>.json

# 4. Only while the image is private: a GitHub token with read:packages
kubectl -n home-stock create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=jamespark89 --docker-password=<token>
```

## Who can sign in

The app has no login of its own. In the Cloudflare dashboard, under
Zero Trust > Access > Applications, add a self-hosted application for
`homestock.jamespark.dev` with an Allow policy listing the household's email
addresses. Do this before the first sync, so the site is never open.

To change a setting: edit prod.env, re-create `home-stock-env` (delete it, then
create it again), then `kubectl -n home-stock rollout restart deployment/home-stock`.

## Price tracking (changedetection.io)

`changedetection` checks shops' product pages for prices, at
https://prices.jamespark.dev (same tunnel; add that hostname to the Home Stock
Access application's destinations, or the tunnel refuses every request).
`sockpuppetbrowser` is the headless Chrome it uses for pages that need
JavaScript. Watches live on the `changedetection-data` volume, which the nightly
backup doesn't cover; changedetection's own Backups page can download them.
The tunnel only reads its config at start, so after changing `cloudflare.yaml`:
`kubectl -n home-stock rollout restart deployment/cloudflared`.

## Releasing

Pushing to the app's `main` builds `ghcr.io/jamespark89/home-stock:sha-<commit>`
(for amd64, the cluster node). Set that tag as `newTag` in `kustomization.yaml` and push; Flux
deploys it, and the `migrate` init container applies any new database
migrations first.

## Backups and restore

`home-stock-db-backup` dumps the database at 3am every night into the
`home-stock-backups` volume, keeping 14 days. The volumes use local-path
storage on the node, so also copy dumps off the machine now and then:

```sh
pod=$(kubectl -n home-stock get pod -l app=home-stock-db -o name)
kubectl -n home-stock exec $pod -- pg_dump -U postgres homestock | gzip > homestock-$(date +%F).sql.gz
```

Restore (replaces everything):

```sh
gunzip -c homestock-<date>.sql.gz | kubectl -n home-stock exec -i $pod -- psql -U postgres -d homestock
```

Careful: deleting this folder from git makes Flux delete the namespace, and
local-path deletes volume data with it.
