# Changelog

## 0.7.10

### Features

- Added `global.appVersion` (default empty). Sets the `APP_VERSION` env var on all workloads,
  falling back to `global.image.tag` as before. Useful when the image tag is a commit sha but
  the app should report a release version.

## 0.7.8

### Fixes

- `workers[].enabled: false` no longer renders the worker. Helm's `default` treats `false` as
  empty, so the flag was ignored and disabled workers were deployed anyway. Affects the
  Deployment, the HorizontalPodAutoscaler and the KEDA ScaledObject.

## 0.7.7

### Features

- Added `global.metrics.enabled` (default `false`). When enabled, the app pods are labelled
  `laravel.keepcloud.io/metrics: "true"`, declare container port `8081`, and a dedicated
  `<release>-metrics` ClusterIP Service is rendered. Requires an image that serves
  `GET /_metrics/queue-size` on port 8081.
- Added `workers[].autoscaling.mode` (`hpa` by default, or `keda`). With `keda`, a
  `ScaledObject` is rendered instead of an `HorizontalPodAutoscaler`, scaling on queue depth
  read from the metrics endpoint and scaling to zero by default.
- Added `workers[].autoscaling.targetValue` (queue depth per replica, default `10`) and
  `workers[].autoscaling.cooldownPeriod`, both used only by `mode: keda`.

## 0.7.6

### Features

- Added `queueOptions` at the top level: chart-wide default flags for `queue` and `combined`
  workers, defaulting to `maxTime: 3600` and `memory: 128`. A worker's own `queueOptions` still
  wins, and setting a key to `null` on the worker drops the flag even when a default exists.

## 0.7.5

### Features

- Added `workerResources`, per-type fallback requests and limits (`queue`, `horizon`,
  `scheduler`, `combined`) applied to any worker that does not set `resources` itself.
  Previously a worker without `resources` got none at all.

### Changes

- Lowered the default `app` CPU request from `50m` to `15m` and raised the CPU limit from
  `500m` to `1000m`.

## 0.7.4

### Changes

- Relaxed the default health check timings for `app` and `reverb`: `initialDelaySeconds` 5 to
  30, `periodSeconds` 15/10 to 30, `timeoutSeconds` 10 to 5. Slow-booting apps were being
  restarted before they became ready.

## 0.7.3

### Features

- Added Laravel Octane support under `app.octane` (`enabled`, `workers`, `logLevel`), with a
  dedicated readiness probe.
- Added `workers[].queueOptions` (`sleep`, `tries`, `timeout`, `maxTime`, `memory`, `backoff`),
  rendered as `php artisan queue:work` flags.

## 0.7.2

### Fixes

- Restored the `app` selector to `app.kubernetes.io/name: <name>-app`, the label used up to
  0.6.25. 0.7.0 had switched it to `app.kubernetes.io/name: <name>` plus
  `app.kubernetes.io/component: app` without listing it as a breaking change, which breaks
  `helm upgrade` on an existing release because `spec.selector` is immutable.

  Upgrading from 0.6.x straight to 0.7.2 or later needs nothing: the selector is the same one
  0.6.x used. Only releases sitting on 0.7.0 or 0.7.1 have to swap the Deployment out:

  ```bash
  kubectl -n <ns> delete deployment <release>-app --cascade=orphan
  helm upgrade ...
  # the orphaned pods keep the 0.7.0 labels and are never adopted, drop them once
  # the new ones are ready
  kubectl -n <ns> delete pod -l app.kubernetes.io/name=laravel,app.kubernetes.io/component=app
  ```

## 0.7.1

### Features

- Added a TLS shorthand to `routing.ingress.routes[].tls`: a plain list of hostnames alongside
  the full Kubernetes Ingress TLS objects.

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
  octane:
    enabled: false
    workers: auto
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
    queueOptions:
      sleep: 3
      tries: 3
      timeout: 90
```

The chart passes worker commands as container args and does not override the image entrypoint, so Server Side Up image initialization still runs before the worker command. If `global.workerCommand.useWrapper=false`, `queue`, `horizon`, and `scheduler` workers fall back to direct `php artisan` commands. `combined` workers are rejected because they require the image wrapper to supervise scheduler and queue processes.

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
