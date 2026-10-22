# Web Helm chart

A Helm chart for deploying stateless HTTP applications. It does not depend on the runtime:
any image that meets the [image requirements](#image-requirements) works. Only the optional
`node.maxOldSpaceFromLimit` helper is specific to Node.js.

The values follow the [Laravel chart](../laravel/) layout wherever the concept is the same:
`global`, `app`, `workers`, `routing.ingress` and `hooks` keep their key names and behaviour.

## Requirements

- Helm 4
- Kubernetes 1.30 or later (the default preStop uses the native `sleep` action)
- A container image that meets the requirements below
- A values file containing `global.image.repository` and `global.image.tag` or `global.image.digest`

The chart does not build or provide the application image.

### Image requirements

The chart runs the image `CMD` and checks it over HTTP or TCP only, so any runtime works
when the image:

1. Listens on `PORT` (or a fixed port declared in `app.port`) on all interfaces, not only
   `localhost`. Set `app.host: 0.0.0.0` for servers that read `HOST`.
2. Serves a lightweight health endpoint, e.g. `GET /up`, that does not depend on databases
   or other services.
3. Runs as a non-root user with a numeric UID (`USER 1000`). With a user name such as
   `USER node`, set `global.podSecurityContext.runAsUser`.
4. Exits cleanly on `SIGTERM` within `terminationGracePeriodSeconds`. For Node, run `node`
   directly as the `CMD`: `npm start` may not forward the signal.
5. Contains `sh` when `hooks.*.commands` are used.
6. Writes only to `global.writablePaths` when `readOnlyRootFilesystem` is enabled.

[`examples/node.Dockerfile`](../../examples/node.Dockerfile) is a reference multi-stage
image for a Node server.

## Installation

Minimal values file:

~~~yaml
global:
  image:
    repository: ghcr.io/example/web
    tag: "1.2.3"

app:
  healthCheck:
    path: /up
~~~

Install the chart:

~~~
helm upgrade --install web ./charts/web \
  --namespace web \
  --create-namespace \
  --values values.yaml
~~~

With default values the chart renders one Deployment (1 replica, image `CMD`, port 3000)
and one ClusterIP Service. Everything else is opt-in.

See [`examples/regrab-web-staging.yaml`](../../examples/regrab-web-staging.yaml) for a
complete deployment with two replicas, an Ingress and cert-manager TLS.

## Configuration

### Port, PORT and HOST

`app.port` (default `3000`) sets the container port, the Service target port, the probe port
and the `PORT` env var. Most frameworks read `PORT`; when the server listens elsewhere, set
`app.port` to that port. If `env` already defines `PORT`, the chart leaves it untouched: keep
it equal to `app.port`. The chart only sees `env`: a `PORT` from an `envFrom` source is
overridden by the injected one.

Set `app.host: 0.0.0.0` to inject `HOST` the same way, for servers that bind to `localhost`
by default (Nuxt, Astro, Remix and similar).

### Command

No `command` or `args` are rendered by default, so the image `ENTRYPOINT` and `CMD` run.
Set `command` and/or `args` on `app`, any worker or any CronJob to override them.

### Probes

The chart generates startup, readiness and liveness probes on `app.healthCheck.path`
(default `/`) and `app.port`, with the Laravel chart's timings: startup allows two minutes
for a cold boot, readiness starts immediately and checks every five seconds, liveness uses
`healthCheck` timings. `app.healthCheck.type: tcp` switches all three to a TCP check.

Customize `app.startupProbe`, `app.readinessProbe` and `app.livenessProbe` independently.
Omitted or `null` values retain the generated probe; `false` disables that probe. An object
overrides its fields. Timing-only overrides retain the generated check, while an `httpGet`,
`exec`, `tcpSocket` or `grpc` handler replaces it entirely. Specify at most one handler.
`app.healthCheck.enabled: false` disables all three probes.

~~~yaml
app:
  livenessProbe:
    exec:
      command: [node, healthcheck.mjs]
  readinessProbe:
    tcpSocket:
      port: http
  startupProbe:
    failureThreshold: 150  # five minutes
  progressDeadlineSeconds: 900
~~~

Workers render no probes unless their `startupProbe`, `readinessProbe` or `livenessProbe` is
set; the object is used as-is.

### Graceful shutdown and rollout

On termination the app container first sleeps `app.preStopSleepSeconds` (default 5) so the
Service and ingress stop routing to it, then receives `SIGTERM`, and is killed after
`app.terminationGracePeriodSeconds` (default 30). The sleep must be shorter than the grace
period. `app.preStopSleepSeconds: 0` removes it; `app.lifecycle` replaces it entirely, for
example with an `exec` hook on clusters older than 1.30.

The Deployment uses `RollingUpdate` with `maxUnavailable: 0` and `maxSurge: 25%`
(`app.rollingUpdate`), and keeps `global.revisionHistoryLimit` (default 3) revisions.

### Security

Every pod runs with `runAsNonRoot: true` and the `RuntimeDefault` seccomp profile; every
container drops all capabilities and disallows privilege escalation. The API token is not
mounted unless `serviceAccount.automountServiceAccountToken` is true.

With `runAsNonRoot`, Kubernetes refuses to start an image whose `USER` is a name rather than
a number, because it cannot verify the user. Set the numeric UID in that case, e.g. for the
official Node images (`USER node`):

~~~yaml
global:
  podSecurityContext:
    runAsUser: 1000
    runAsGroup: 1000
~~~

Read-only root filesystem, with an `emptyDir` on every path the app writes to:

~~~yaml
global:
  securityContext:
    readOnlyRootFilesystem: true
  writablePaths:
    - /tmp
    - /app/.cache
~~~

The emptyDirs are mounted on every workload, hooks and CronJobs included.

### Environment variables and Secrets

~~~yaml
global:
  env:
    - name: API_URL
      value: https://api.example.com
  envFrom:
    - secretRef:
        name: web-secrets

app:
  env:
    - name: SESSION_SECRET
      valueFrom:
        secretKeyRef:
          name: web-secrets
          key: session
~~~

Env vars are rendered in this order: chart-owned (`APP_VERSION`, `CONTAINER_ROLE`), injected
(`PORT`, `HOST`, `NODE_OPTIONS`, each only when `env` does not define it), `global.env`, then
the workload's `env`. `APP_VERSION` (from `global.appVersion`, falling back to
`global.image.tag`) and `CONTAINER_ROLE` (`app`, `worker`, `cron`, `pre-deploy`,
`post-deploy`) cannot be overridden through `env`.

Each pod carries a `checksum/env` annotation computed over its `env` and `envFrom` values.
It does not cover the contents of referenced Secrets or ConfigMaps: after changing a Secret,
restart the pods with `kubectl rollout restart`.

`global.secretVolumes` mounts Secret keys as files, as in the Laravel chart.

### Node memory helper (Node.js only)

~~~yaml
app:
  node:
    maxOldSpaceFromLimit: true
  resources:
    limits:
      memory: 1Gi  # NODE_OPTIONS=--max-old-space-size=768
~~~

Sets `NODE_OPTIONS=--max-old-space-size` to 75% of the memory limit in MiB, leaving room for
memory outside the V8 heap. It applies only when a memory limit is set and `env` does not
define `NODE_OPTIONS`. The limit must be an integer with an optional `Ki`, `Mi`, `Gi`, `Ti`,
`k`, `M`, `G` or `T` suffix. Workers and CronJobs accept the same `node` key. Other runtimes
ignore `NODE_OPTIONS`; leave the helper off.

### Scaling and availability

~~~yaml
app:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 60
    targetMemoryUtilizationPercentage: 80
    behavior:
      scaleDown:
        stabilizationWindowSeconds: 300
~~~

At least one target is required. A PodDisruptionBudget with `minAvailable` (default 1) is
rendered when `replicas` is above 1, or when autoscaling is enabled and `minReplicas` is
above 1.

App and worker pods are spread across nodes (`kubernetes.io/hostname`, `maxSkew: 1`,
`ScheduleAnyway`, `nodeTaintsPolicy: Honor`). A workload's `topologySpreadConstraints` list
replaces the default, `[]` disables it, and `global.topologySpreadConstraints` applies to
workloads that set none.

### Workers

Each item renders a Deployment from the same image with its own command, plus an HPA and a
PDB on the same conditions as the app:

~~~yaml
workers:
  - name: jobs
    command: [node, dist/worker.mjs]
    replicas: 2
    resources:
      requests:
        cpu: 10m
        memory: 128Mi
      limits:
        memory: 512Mi
    livenessProbe:
      exec:
        command: [node, dist/worker-health.mjs]
    terminationGracePeriodSeconds: 120
~~~

Worker HPAs default to `minReplicas: 1`, `maxReplicas: 5` and 80% CPU. The Laravel chart's
KEDA mode is not available: it scales on a Laravel queue-size endpoint that generic apps
do not expose.

### CronJobs

~~~yaml
cronJobs:
  - name: cleanup
    schedule: "0 3 * * *"
    timeZone: Europe/Rome
    command: [node, dist/cleanup.mjs]
    activeDeadlineSeconds: 600
~~~

`concurrencyPolicy` defaults to `Forbid`. History limits and `backoffLimit` use the
Kubernetes defaults unless set.

### Pre-deploy and post-deploy hooks

~~~yaml
hooks:
  preDeploy:
    enabled: true
    commands:
      - node dist/migrate.mjs
    backoffLimit: 0
    activeDeadlineSeconds: 600
~~~

Commands run in order through `sh -c` and stop at the first failure, so the image needs a
shell. The pre-deploy Job runs before each upgrade and blocks it when it fails; on the first
install it runs after the release resources are created, so the app can start before the
commands complete; it still runs before the post-deploy Job. The post-deploy Job runs after
install and upgrade. Both use the app
image, global env, their own `env`/`envFrom`, and global secret volumes.

### Ingress

~~~yaml
routing:
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt
    routes:
      - service: app
        host: example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - example.com
~~~

Same shape as the Laravel chart; routes can only target `app`. `tls` accepts hostnames
(sharing a `<fullname>-tls` secret) or full Kubernetes Ingress TLS objects. With Traefik's
nginx compatibility, keep `className: nginx`.

### Metrics

`global.metrics.enabled` adds a `metrics` container port (`global.metrics.port`, default
9090) to the app pods and a `<fullname>-metrics` Service. `global.metrics.serviceMonitor.enabled`
also renders a Prometheus Operator ServiceMonitor scraping `global.metrics.path`.

### Extensibility

`extraVolumes`, `extraVolumeMounts` (global and per workload, concatenated),
`initContainers`, `extraContainers`, `podAnnotations`, `podLabels`, `priorityClassName`,
`dnsConfig` and the scheduling keys are available on `app`, every worker and every CronJob.

## Values

| Key | Default | Description |
| --- | --- | --- |
| `global.image.repository` | `""` | Image repository. Required. |
| `global.image.tag` | `""` | Image tag. Required unless `digest` is set. |
| `global.image.digest` | `""` | Image digest; takes precedence over `tag`. |
| `global.image.pullPolicy` | `IfNotPresent` | Image pull policy. |
| `global.appVersion` | `""` | `APP_VERSION` value; defaults to `global.image.tag`. |
| `global.imagePullSecrets` | `[]` | Pull secrets for every pod. |
| `global.env` | `[]` | Env vars for every container. |
| `global.envFrom` | `[]` | envFrom sources for every container. |
| `global.secretVolumes` | `[]` | Secret keys mounted as files. |
| `global.podAnnotations` | `{}` | Annotations for every pod. |
| `global.podLabels` | `{}` | Labels for every pod. |
| `global.podSecurityContext` | `runAsNonRoot`, `RuntimeDefault` | Pod securityContext. |
| `global.securityContext` | no escalation, drop `ALL`, `readOnlyRootFilesystem: false` | Container securityContext. |
| `global.writablePaths` | `[/tmp]` | emptyDir mounts when the root filesystem is read-only. |
| `global.extraVolumes` | `[]` | Volumes for every pod. |
| `global.extraVolumeMounts` | `[]` | Volume mounts for every main container. |
| `global.nodeSelector` | `{}` | Merged with the workload's. |
| `global.tolerations` | `[]` | Used when the workload sets none. |
| `global.affinity` | `{}` | Merged with the workload's. |
| `global.topologySpreadConstraints` | `[]` | Used when the workload sets none. |
| `global.priorityClassName` | `""` | Used when the workload sets none. |
| `global.dnsConfig` | `{}` | Used when the workload sets none. |
| `global.revisionHistoryLimit` | `3` | Revisions kept by every Deployment. |
| `global.metrics.enabled` | `false` | Metrics port and Service. |
| `global.metrics.port` | `9090` | Metrics port. |
| `global.metrics.path` | `/metrics` | Scrape path. |
| `global.metrics.serviceMonitor.enabled` | `false` | Render a ServiceMonitor. |
| `global.metrics.serviceMonitor.interval` | `30s` | Scrape interval. |
| `global.metrics.serviceMonitor.labels` | `{}` | Extra ServiceMonitor labels. |
| `serviceAccount.create` | `false` | Create a ServiceAccount. |
| `serviceAccount.name` | `""` | ServiceAccount name; fullname when created, `default` otherwise. |
| `serviceAccount.annotations` | `{}` | Annotations of the created ServiceAccount. |
| `serviceAccount.automountServiceAccountToken` | `false` | Mount the API token in pods. |
| `app.enabled` | `true` | Render the app Deployment and Service. |
| `app.replicas` | `1` | Replicas without autoscaling. |
| `app.minAvailable` | `1` | PDB minAvailable. |
| `app.port` | `3000` | Container port and `PORT` env. |
| `app.host` | `""` | `HOST` env when set. |
| `app.command` / `app.args` | `[]` | Override the image ENTRYPOINT / CMD. |
| `app.env` / `app.envFrom` | `[]` | Appended after the global ones. |
| `app.podAnnotations` / `app.podLabels` | `{}` | Merged over the global ones. |
| `app.nodeSelector` / `app.tolerations` / `app.affinity` | | Scheduling overrides. |
| `app.topologySpreadConstraints` | `null` | `null` spreads across nodes; `[]` disables. |
| `app.priorityClassName` / `app.dnsConfig` | | Pod overrides. |
| `app.extraVolumes` / `app.extraVolumeMounts` | `[]` | Appended after the global ones. |
| `app.initContainers` / `app.extraContainers` | `[]` | Init and sidecar containers. |
| `app.service.enabled` | `true` | Render the Service. |
| `app.service.type` | `ClusterIP` | Service type. |
| `app.service.port` | `null` | Service port; defaults to `app.port`. |
| `app.healthCheck.enabled` | `true` | Render the probes. |
| `app.healthCheck.type` | `http` | `http` or `tcp`. |
| `app.healthCheck.path` | `/` | Health endpoint path. |
| `app.healthCheck.port` | `null` | Probe port; defaults to `app.port`. |
| `app.healthCheck.initialDelaySeconds` | `30` | Liveness initial delay. |
| `app.healthCheck.periodSeconds` | `30` | Liveness period. |
| `app.healthCheck.timeoutSeconds` | `5` | Readiness and liveness timeout. |
| `app.healthCheck.failureThreshold` | `3` | Readiness and liveness threshold. |
| `app.startupProbe` / `readinessProbe` / `livenessProbe` | `null` | Probe overrides; `false` disables. |
| `app.progressDeadlineSeconds` | `null` | Deployment progress deadline. |
| `app.rollingUpdate` | `maxUnavailable: 0`, `maxSurge: 25%` | RollingUpdate settings. |
| `app.terminationGracePeriodSeconds` | `30` | Grace period. |
| `app.preStopSleepSeconds` | `5` | preStop sleep; `0` disables. |
| `app.lifecycle` | `{}` | Replaces the generated preStop. |
| `app.resources` | 10m/128Mi requests, 1000m/512Mi limits | Container resources. |
| `app.autoscaling.enabled` | `false` | Render an HPA. |
| `app.autoscaling.minReplicas` | `1` | HPA minimum. |
| `app.autoscaling.maxReplicas` | `10` | HPA maximum. |
| `app.autoscaling.targetCPUUtilizationPercentage` | `60` | CPU target. |
| `app.autoscaling.targetMemoryUtilizationPercentage` | `null` | Memory target. |
| `app.autoscaling.behavior` | `{}` | HPA behavior. |
| `app.node.maxOldSpaceFromLimit` | `false` | Node-only `NODE_OPTIONS` helper. |
| `workers[]` | `[]` | `name` (required), `enabled`, `command`, `args`, `replicas`, `minAvailable`, `resources`, `env`, `envFrom`, probes, `terminationGracePeriodSeconds`, `lifecycle`, `node`, `autoscaling`, and the pod keys of `app`. |
| `cronJobs[]` | `[]` | `name`, `schedule` (required), `enabled`, `timeZone`, `command`, `args`, `concurrencyPolicy` (`Forbid`), `successfulJobsHistoryLimit`, `failedJobsHistoryLimit`, `backoffLimit`, `activeDeadlineSeconds`, `resources`, `env`, `envFrom`, `node`, and the pod keys of `app`. |
| `routing.ingress.enabled` | `false` | Render the Ingress. |
| `routing.ingress.className` | `""` | ingressClassName. |
| `routing.ingress.annotations` | `{}` | Ingress annotations. |
| `routing.ingress.routes` | `[]` | `{service: app, host, paths[{path, pathType}]}`. |
| `routing.ingress.tls` | `[]` | Hostnames or Ingress TLS objects. |
| `hooks.preDeploy.*` / `hooks.postDeploy.*` | disabled | `enabled`, `commands`, `env`, `envFrom`, `resources`, `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`. |

## Examples

App with a worker and a CronJob:

~~~yaml
global:
  image:
    repository: ghcr.io/example/api
    tag: "2.0.0"
  envFrom:
    - secretRef:
        name: api

app:
  replicas: 2
  healthCheck:
    path: /health

workers:
  - name: jobs
    command: [node, dist/worker.mjs]

cronJobs:
  - name: cleanup
    schedule: "0 3 * * *"
    command: [node, dist/cleanup.mjs]
~~~

App with a migration hook:

~~~yaml
global:
  image:
    repository: ghcr.io/example/api
    tag: "2.0.0"
  envFrom:
    - secretRef:
        name: api

hooks:
  preDeploy:
    enabled: true
    commands:
      - node dist/migrate.mjs
    backoffLimit: 0
~~~

Read-only root filesystem for a Go service listening on 8080:

~~~yaml
global:
  image:
    repository: ghcr.io/example/svc
    tag: "1.0.0"
  podSecurityContext:
    runAsUser: 65532
  securityContext:
    readOnlyRootFilesystem: true

app:
  port: 8080
  healthCheck:
    path: /healthz
~~~

## Validation and rendering

~~~
helm lint ./charts/web -f values.yaml
helm template web ./charts/web --namespace web --values values.yaml
helm unittest --strict ./charts/web
~~~

## References

- [Default values](values.yaml)
- [Values schema](values.schema.json)
- [Changelog](CHANGELOG.md)
