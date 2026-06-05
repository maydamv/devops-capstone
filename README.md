# DevOps Capstone — Node.js CI/CD (CS411)

A small Express app (`index.js`) serving JSON on port **4444**, with a full
build-and-deploy pipeline: unit test → Docker image → push → deploy to a
Docker host, a Kubernetes cluster, and a systemd target.

## App

- `GET /` returns `{ "name": "Hello", "description": "World", "url": <host> }`
- `index.test.js` is a `node:test` unit test for the `Sample()` function.

## Run locally

```bash
npm install
npm start            # http://localhost:4444
npm test             # node --test
```

## Build & run the container

```bash
docker build -t myapp .
docker run -d -p 4444:4444 myapp
curl http://localhost:4444/        # -> {"name":"Hello",...}
docker inspect --format '{{.State.Health.Status}}' <container>   # -> healthy
```

## Pipeline (Jenkins)

`Jenkinsfile` defines the stages:

1. **Unit test** — runs `node --test` inside a `node:24-alpine` container
   (so the agent needs no Node install).
2. **Build image** — `docker build` tagged `ttl.sh/maydamv-capstone-cs411:2h`.
3. **Push** — to the anonymous `ttl.sh` registry.
4. **Deploy: docker VM** — `ssh` + `docker run -d -p 4444:4444`.
5. **Deploy: Kubernetes** — `kubectl apply` the Deployment + Service, then
   `rollout status`.
6. **Deploy: target VM (systemd)** — ship the source, `npm install`, run
   `node index.js` under a non-root `myapp` systemd unit.
7. **Health check** — `curl` the endpoint on the target and docker hosts.

### Credentials the pipeline expects (Jenkins → Manage Credentials)

| ID           | Kind                            | Used for                     |
|--------------|---------------------------------|------------------------------|
| `target-ssh` | SSH username with private key   | ssh/scp to `target`, `docker`|
| `k8s-token`  | Secret text (ServiceAccount JWT)| `kubectl` to the cluster     |

## Verify the Kubernetes deployment

```bash
kubectl get pods -l app=myapp           # pod Running / Ready
kubectl get svc myapp                   # ClusterIP on 4444
kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://myapp:4444/            # JSON through the Service
```

## Kubernetes manifests

- `k8s/deployment.yaml` — Deployment `myapp` (liveness/readiness probes on
  4444, resource requests + limits).
- `k8s/service.yaml` — ClusterIP Service `myapp` targeting 4444.
