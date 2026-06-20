# Changelog

## 0.7.0

### Breaking changes

- Reorganized `values.yaml` around service and workload scopes.
- Moved image settings to `global.image.repository`, `global.image.tag`, and `global.image.pullPolicy`.
- Replaced separate `horizon`, `queueWorkers`, and `scheduler` values with a unified `workers[]` list.
- Removed scheduler CronJob mode. Scheduler workers now render as a single-replica Deployment.
- Added `combined` worker type for low-traffic apps. It requires `global.workerCommand.useWrapper=true`.
- Moved `service` under each networked workload: `app.service` and `reverb.service`.
- Replaced top-level `ingress` and `redirect` with `routing.ingress.routes[]`. Redirects should be configured through ingress annotations.
- Removed `options.allowArmNodes`, `options.disableDefaultEnv`, and `options.disableDefaultAppAffinity`.
- Removed default `LOG_CHANNEL`; chart-owned env now only includes operational metadata.

### Migration guide

Image:

```yaml
deployment:
  images:
    app: ghcr.io/acme/app
  version: 1.2.3
  pullPolicy: IfNotPresent
```

becomes:

```yaml
global:
  image:
    repository: ghcr.io/acme/app
    tag: 1.2.3
    pullPolicy: IfNotPresent
```

App deployment:

```yaml
deployment:
  enabled: true
  replicaCount: 2
  port: 80
  resources: {}
autoscaling: {}
service:
  type: ClusterIP
  port: 80
```

becomes:

```yaml
app:
  enabled: true
  replicas: 2
  port: 8080
  resources: {}
  autoscaling: {}
  service:
    type: ClusterIP
    port:
```

Queue workers:

```yaml
queueWorkers:
  enabled: true
  queues:
    - name: default
      replica: 2
```

becomes:

```yaml
workers:
  - name: default
    type: queue
    enabled: true
    replicas: 2
    queue: default
```

Horizon:

```yaml
horizon:
  enabled: true
  autoscaling: {}
```

becomes:

```yaml
workers:
  - name: horizon
    type: horizon
    enabled: true
    replicas: 1
    autoscaling: {}
```

Scheduler:

```yaml
scheduler:
  enabled: true
  cron: false
```

becomes:

```yaml
workers:
  - name: scheduler
    type: scheduler
    enabled: true
```

Combined low-traffic worker:

```yaml
global:
  workerCommand:
    useWrapper: true
    binary: docker-laravel-worker
workers:
  - name: combined
    type: combined
    enabled: true
    queue: default,emails
```

If `global.workerCommand.useWrapper=false`, `queue`, `horizon`, and `scheduler` workers fall back to direct `php artisan` commands. `combined` workers are rejected because they require the image wrapper to supervise scheduler and queue processes.

Ingress:

```yaml
ingress:
  enabled: true
  hosts:
    - host: example.com
      paths:
        - /
redirect:
  enabled: true
```

becomes:

```yaml
routing:
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/from-to-www-redirect: "true"
    routes:
      - service: app
        host: example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - example.com
```

Post-deploy hook:

```yaml
hooks:
  postDeploy:
    enabled: true
    command:
      - php artisan migrate --force -n
      - php artisan db:seed --force
```

becomes:

```yaml
hooks:
  postDeploy:
    enabled: true
    commands:
      - php artisan migrate --force -n
      - php artisan db:seed --force
```

The template still accepts `hooks.postDeploy.command` for migration, but `commands` is canonical.
