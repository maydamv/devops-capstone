# PROMPTS.md — Capstone (Node.js transfer)

**Agent:** Claude Code (Opus 4.x), interactive session
**Repo:** https://github.com/maydamv/devops-capstone

## Transfer story: did I reuse the Go prompts, or re-derive for Node.js?

I **re-derived** the pipeline for Node instead of copy-pasting the Go prompts,
because the language change breaks the assumption most of the Go flow rested
on. In the homework, the artifact was a single self-contained binary: build
once, `scp` one file, run it — no runtime on the target. Node isn't like that.
The artifact is *source plus a runtime plus dependencies*, so every stage that
touched "the binary" had to be rethought. I went stage by stage and asked what
each one actually means now, rather than search-replacing "go build" with
"npm".

## A specific prompt I used

> "I'm porting my Go deploy pipeline to a Node.js app. In Go the target VM
> just ran one static binary under systemd. For Node, what does the
> equivalent systemd deploy need on the target that the Go one didn't, and
> what should ExecStart be?"

The key thing the answer surfaced: unlike the Go binary, the target now needs
the **Node runtime installed** and an `npm install` of the dependencies in the
app directory before systemd can start anything, and the unit's `ExecStart`
becomes `node /opt/myapp/index.js` (an interpreter + script) instead of a path
to a binary. That single difference rippled through the whole `target` stage.

## A friction moment

The Docker base image. My Go image used `scratch`/a static binary — that
instinct is wrong for Node: there is no static Node binary, the app needs the
interpreter and `node_modules`. I switched the base to `node:24-alpine`, which
also conveniently keeps the image small *and* ships busybox `wget` for the
`HEALTHCHECK`. The other friction was the unit test: I didn't want to install
Node on the Jenkins agent just to run `node --test`, so I run the test inside a
`node:24-alpine` container with the workspace mounted — Node 24 for the test,
nothing installed on the agent.

## A verification step

After each deploy I verify the *running* app, not just that a command exited 0:

- Unit test: `node --test` must pass in the Node 24 container before anything
  is built.
- Container: `curl http://localhost:4444/` returns the JSON and
  `docker inspect --format '{{.State.Health.Status}}'` reports `healthy`.
- Kubernetes: `kubectl rollout status deployment/myapp` then curl the Service.
- Target/docker VMs: the pipeline's health-check stage curls `:4444` on each
  host and greps for `"name":"Hello"` before calling the build green.

## What stayed the same (language-agnostic)

The Kubernetes Deployment/Service and the SSH-credential-by-ID pattern carried
over almost unchanged from the Go challenges — those describe *where* the app
runs, not *what language* it is, so they didn't need re-derivation. The probes
still hit `/` on 4444; only the JSON key casing changed (`name` vs Go's `Name`).
