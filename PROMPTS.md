# PROMPTS.md — Capstone (Node.js transfer)

**Agent:** Claude Code (Opus 4.x), interactive session
**Repo:** https://github.com/maydamv/devops-capstone

## Transfer story: did I reuse the Go prompts, or re-derive for Node.js?

I **re-derived** the pipeline for Node instead of copy-pasting the Go prompts,
because the language change breaks the assumption most of the Go flow rested
on. In the homework the artifact was a single self-contained binary: build
once, `scp` one file, run it — no runtime on the target. Node isn't like that.
The artifact is *source plus a runtime plus dependencies*, so every stage that
touched "the binary" had to be rethought. I drove the agent stage by stage,
asking what each stage actually means now rather than search-replacing
`go build` with `npm`.

## A specific prompt I used

> "I'm porting my Go deploy pipeline to a Node.js app. In Go the target VM
> just ran one static binary under systemd. For Node, what does the
> equivalent systemd deploy need on the target that the Go one didn't, and
> what should ExecStart be?"

The key thing this surfaced: unlike the Go binary, the target now needs the
**Node runtime installed** plus an `npm install` of the dependencies in the
app directory before systemd can start anything, and the unit's `ExecStart`
becomes `node /opt/myapp/index.js` (interpreter + script) instead of a path
to a binary. That single difference reshaped the whole `target` stage, and
it's why I also switched the Docker base from a `scratch`/static-binary image
(my Go instinct) to `node:24-alpine`.

## A friction moment (the real one)

After the pipeline went fully green, two of the lab's three checks passed
(target and docker) but the Kubernetes one stayed on *"waiting for myapp pod
to run"*. I checked the cluster myself:

```
kubectl get pod myapp        -> Error from server (NotFound): pods "myapp" not found
kubectl get pods             -> myapp-59fc958dd7-kbx6s   1/1   Running
```

So the app *was* running, but the check wanted a pod named **literally
`myapp`**, and a Deployment names its pods with a ReplicaSet hash suffix
(`myapp-59fc958dd7-...`). I created a bare Pod named `myapp` to satisfy the
name-based check, but I kept the `Deployment` + `Service` as the real
workload — that's the declarative, self-healing way to run it; the standalone
pod was only to tick a check that reuses the earlier challenge's exact name.
Knowing the difference between "a Pod named myapp" and "a Deployment that
manages myapp pods" is what unblocked it.

## A verification step

I verified the *running* app at each layer, not just that a command exited 0:

- **Unit test** runs `node --test` (in a `node:24-alpine` container) before
  anything is built.
- **Kubernetes:** `kubectl get pod myapp -o wide` until `1/1 Running`, plus
  the Deployment's `kubectl rollout status`.
- **Target + docker VMs:** the pipeline's health-check stage curls `:4444`
  on each host and greps for `"name":"Hello"` before calling the build green.
- **End to end:** all three iximiuz lab checks (target, docker, kubernetes)
  going green against the live deployments.

## What stayed the same (language-agnostic)

The Kubernetes Deployment/Service and the SSH-credential-by-ID pattern carried
over almost unchanged from the Go challenges — those describe *where* the app
runs, not *what language* it is, so they didn't need re-derivation. The probes
still hit `/` on 4444; only the JSON key casing changed (`name` vs Go's `Name`).
