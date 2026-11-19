# DevOpsAssessment – Deployment, Release & Recovery

Containerised deployment of the supplied ASP.NET Core (.NET 10) application on an
Ubuntu 24.04 EC2 instance, with an Nginx reverse proxy, GitHub Actions CI publishing
versioned images to GHCR, scripted deploy/rollback with a bounded health check,
and health monitoring with failure detection and recovery.

## 1. Architecture

```
 Browser / curl
      │  :80 (only port published; security group allows 22 + 80 from my IP)
      ▼
 ┌──────────── EC2 (Ubuntu 24.04, Docker + Compose v2) ─────────────┐
 │  nginx:1.28-alpine  ──(internal Docker network)──►  app :8080    │
 │  published 80:80                                    expose only  │
 │                                                     non-root     │
 └──────────────────────────────────────────────────────────────────┘
      ▲ docker pull ghcr.io/meesam-devops/devops-assessment:<tag>
 GitHub Actions: build → smoke test → push (on tag vX.Y.Z)
```

| Endpoint | Purpose |
|---|---|
| `GET /` | App info and configurable message |
| `GET /health` | `200 Healthy` while the app is healthy |
| `GET /version` | Configured `APP_VERSION` |

## 2. Repository layout

| Path | Purpose |
|---|---|
| `Dockerfile` | Multi-stage build (SDK → ASP.NET runtime), non-root, healthcheck |
| `.dockerignore` | Keeps `.env`, `.git`, scripts, docs out of the build context and image |
| `docker-compose.yml` | `app` + `nginx`, healthcheck, restart policy, log rotation, hardening |
| `nginx/default.conf` | Reverse proxy to `app:8080` |
| `.env.example` / `app.env.example` | Configuration templates (real `.env` / `app.env` are git-ignored) |
| `scripts/deploy.sh` | Deploy a specific image tag, check `/health` through the proxy with a timeout |
| `scripts/rollback.sh` | Redeploy the previously deployed tag |
| `scripts/monitor.sh` | Health monitor, exit code 0/1 + `ALERT` line + syslog entry |
| `scripts/smoke-test.sh` | CI smoke test of a built image |
| `.github/workflows/ci.yml` | Build → smoke test → publish to GHCR |
| `evidence/` | Captured command output (deploy, rollback, failure, recovery) |

## 3. Prerequisites

- Ubuntu 24.04 (tested on AWS EC2 t3.micro with 2 GB swap, 20 GB gp3)
- Docker Engine and Docker Compose v2, Git
- Security group inbound: 22/tcp and 80/tcp from the admin IP only (8080 is never opened)
- A GitHub token with `read:packages` on the host, to pull from GHCR (private package)

## 4. Setup (reproducible)

```bash
# Docker
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
sudo usermod -aG docker $USER && newgrp docker

# Code + config
git clone https://github.com/meesam-devops/devopsAssignment.git
cd devopsAssignment
cp .env.example .env
cp app.env.example app.env
chmod +x scripts/*.sh

# Registry login (token read from a prompt, never in history or Git)
read -s -p "GHCR token: " T; echo; echo "$T" | docker login ghcr.io -u <github-user> --password-stdin; unset T

# Deploy
./scripts/deploy.sh 1.0.0
curl http://localhost/  ;  curl http://localhost/health  ;  curl http://localhost/version
```

## 5. Configuration

| Variable | File | Purpose | Default / example |
|---|---|---|---|
| `IMAGE_REPO` | `.env` | Image repository | `ghcr.io/meesam-devops/devops-assessment` |
| `APP_TAG` | `.env` | Image tag to run (written by `deploy.sh`) | `1.0.0` |
| `PROXY_PORT` | `.env` | Host port for Nginx | `80` |
| `APP_MESSAGE` | `app.env` | Message returned by `/` | `Assessment deployment successful` |
| `ASPNETCORE_ENVIRONMENT` | `app.env` | App environment | `Production` |
| `APP_VERSION` | compose | Set automatically to `APP_TAG`, so `/version` always matches the running image | — |
| `ASPNETCORE_URLS` | compose | App listen address | `http://+:8080` |
| `HEALTH_URL` | script env | Health URL checked by deploy/monitor | `http://localhost/health` |
| `HEALTH_TIMEOUT` | script env | Max seconds `deploy.sh` waits for health | `60` |
| `INTERVAL` | script env | Seconds between checks in `monitor.sh --loop` | `10` |

All runtime configuration is supplied at run time from `.env` / `app.env`. Nothing is baked into the image.

## 6. CI pipeline (GitHub Actions)

`.github/workflows/ci.yml` runs on every push to `main` and on tags `v*`:

1. **Build**: `docker build --pull` (always the latest patched .NET 10 base images).
2. **Smoke test**: `scripts/smoke-test.sh` starts the image, checks `/health`, `/version`, `/`, and verifies the container is **not** running as root.
3. **Publish**: pushes to GHCR. Tag `v2.0.0` → image `:2.0.0`; branch pushes → `:sha-<commit>`.

The registry login uses the per-run `GITHUB_TOKEN`; no secret is stored in the repository.

Release:
```bash
git tag v2.0.0 && git push origin v2.0.0     # CI builds and publishes :2.0.0
```

## 7. Release and rollback

```bash
./scripts/deploy.sh 2.0.0     # deploy a specific version
./scripts/rollback.sh         # go back to the previously deployed version
./scripts/deploy.sh 1.0.0     # or deploy any earlier tag explicitly
```

`deploy.sh`:
1. Writes `APP_TAG` to `.env` and runs `docker compose up -d --pull missing`.
2. Polls `http://localhost/health` **through Nginx** with a bounded timeout (`HEALTH_TIMEOUT`, default 60 s).
3. On success it records state in `.deploy/` (`current_tag`, `previous_tag`, `history.log`) and prints the version, the response and the image digest.
4. On failure it prints `DEPLOY FAILED`, the container status and the last app logs, names the last good release, and exits 1.

A deploy that fails to pull or start leaves the previously running release serving traffic.

## 8. Monitoring and recovery

- **Container healthcheck** (Dockerfile + compose): calls `/health` every 10 s. Docker marks the container `unhealthy` after 3 failures.
- **Self-healing**: `restart: unless-stopped` restarts the app if the process exits.
- **External monitor**: `scripts/monitor.sh` checks `/health` **through the proxy**.
  - Healthy → `OK ... HTTP 200`, exit 0.
  - Unavailable → `ALERT ... HTTP 502 (application unavailable)` on stderr, exit 1, and a syslog entry tagged `app-monitor`.
  - Run once (`./scripts/monitor.sh`), continuously (`./scripts/monitor.sh --loop`) or from cron:
    ```
    * * * * * /home/ubuntu/project/devopsAssignment/scripts/monitor.sh >/dev/null 2>&1 || true
    ```
    Alerts can then be viewed with `journalctl -t app-monitor`.

## 9. Logs

| What | Command |
|---|---|
| App logs (JSON) | `docker compose logs -f app` |
| App logs, pretty | `docker compose logs --no-log-prefix app \| jq .` |
| Proxy access + error logs | `docker compose logs -f nginx` |
| Time window | `docker compose logs --since 10m app` |
| Monitor alerts | `journalctl -t app-monitor` |

**Log growth control:** both containers use the `json-file` driver with `max-size: 10m`, `max-file: 3`. Each container keeps at most about 30 MB of logs, rotated automatically by Docker.

**Production log retention:** ship container logs to a central store (CloudWatch Logs via the `awslogs` driver or CloudWatch agent, or Loki/ELK). Set retention by policy there (for example 30 days hot and 90 days archived), and keep local rotation as a safety net.

## 10. Security measures

- **Non-root**: the app runs as the image's built-in `app` user (UID 1654); the smoke test fails the build if it runs as root.
- **Hardened container**: `read_only: true` root filesystem (`/tmp` as tmpfs), `cap_drop: [ALL]`, `no-new-privileges`.
- **No direct app exposure**: the app uses `expose: 8080` only. Nginx is the single published port, and the security group does not open 8080.
- **Small runtime image**: multi-stage build, so the SDK and source are not in the final image. No packages are installed in the runtime image; the healthcheck uses bash's built-in `/dev/tcp` instead of curl.
- **Nginx**: `server_tokens off`, connect and read timeouts.
- **Secrets out of Git and images**:
  - `.env` and `app.env` are in `.gitignore` and `.dockerignore`; only `*.example` templates are committed.
  - Nothing secret is passed as `ARG`/`ENV` in the Dockerfile.

**How deployment credentials are supplied:**

| Where | How |
|---|---|
| CI → GHCR | The automatic per-run `GITHUB_TOKEN` (`packages: write`), passed via `--password-stdin` |
| Host → GHCR | A personal token with `read:packages` only, entered at a hidden prompt into `docker login --password-stdin`. Docker stores it in `~/.docker/config.json` (it warns that this is unencrypted) |
| Production | Replace stored tokens with an IAM instance role + ECR (no long-lived credential), or a Docker credential helper. App secrets come from AWS Secrets Manager / SSM Parameter Store or Vault at deploy time. Use SSM Session Manager instead of SSH |

## 11. HTTPS and certificate renewal (production design, not run locally)

**Option A: Let's Encrypt on the host**
1. Point a DNS record (for example `app.example.com`) at the instance (Elastic IP) and open 443 in the security group.
2. Add a `certbot` volume to Nginx and serve `/.well-known/acme-challenge/` from `/var/www/certbot` on port 80.
3. Issue: `certbot certonly --webroot -w /var/www/certbot -d app.example.com`.
4. Nginx: `listen 443 ssl; http2 on;` with `ssl_certificate /etc/letsencrypt/live/app.example.com/fullchain.pem`, TLS 1.2/1.3 only, HSTS header, and a 301 redirect from 80 to 443.
5. **Auto-renewal**: certbot's systemd timer (`certbot renew`, twice a day) with `--deploy-hook "docker compose exec nginx nginx -s reload"`.
6. Monitor certificate expiry, for example alert at fewer than 14 days.

**Option B: AWS-managed**
An Application Load Balancer with a free ACM certificate (renewed automatically by AWS). It terminates TLS and forwards to Nginx/app on the private network.

## 12. Evidence

All evidence is captured in `evidence/`. Credentials, the account ID and the public IP are removed.

| File | Shows |
|---|---|
| `01-deploy-1.0.0.txt` | First deploy, health check via proxy, version, response, image digest |
| `02-deploy-2.0.0.txt` | Upgrade to release 2.0.0 |
| `03-rollback-to-1.0.0.txt` | Rollback 2.0.0 → 1.0.0 |
| `04-failed-deploy.txt` | Non-existent tag 9.9.9 → `DEPLOY FAILED`, exit 1, old release kept serving |
| `06-failure-recovery.txt` | App stopped → `ALERT` / HTTP 502 / exit 1 → restored → `OK` / HTTP 200 / exit 0 |

**Release → upgrade → rollback (two distinct images):**
```
==> Deploying tag '1.0.0' (currently running: none)
==> DEPLOY OK
version : {"version":"1.0.0"}
image   : ghcr.io/meesam-devops/devops-assessment:1.0.0 sha256:757bc1a7977c…

==> Deploying tag '2.0.0' (currently running: 1.0.0)
==> DEPLOY OK
version : {"version":"2.0.0"}
image   : ghcr.io/meesam-devops/devops-assessment:2.0.0 sha256:57a031345d65…

==> ROLLBACK: 2.0.0 -> 1.0.0
==> Deploying tag '1.0.0' (currently running: 2.0.0)
==> DEPLOY OK
version : {"version":"1.0.0"}
image   : ghcr.io/meesam-devops/devops-assessment:1.0.0 sha256:757bc1a7977c…
```

**After rollback: app healthy, only Nginx published:**
```
NAME                        IMAGE                                           STATUS                    PORTS
devops-assessment-app-1     ghcr.io/meesam-devops/devops-assessment:1.0.0   Up 15 seconds (healthy)   8080/tcp
devops-assessment-nginx-1   nginx:1.28-alpine                               Up 3 hours                0.0.0.0:80->80/tcp
```

**Failure detection and recovery** (excerpt from `evidence/06-failure-recovery.txt`):
```
<!-- REPLACE with output of: grep -E "###|OK|ALERT|exit code" evidence/06-failure-recovery.txt -->
```

The screenshots folder holds the green GitHub Actions runs for v1.0.0 and v2.0.0, and the GHCR package tags.

## 13. Incidents during the work (diagnosed and fixed)

| Problem | Root cause | Fix |
|---|---|---|
| CI workflow never ran ("Get started with Actions") | `.gitignore` contained `.dockerignore` patterns (`.github/`, `*.md`), so `ci.yml` was never committed | Corrected `.gitignore` to ignore only secrets and build output; verified with `git check-ignore -v` |
| `docker pull ...:2.0.0` → `not found` | Release tag pointed at a commit without the workflow, so no image was built | Re-created the tags on commits that contain `ci.yml` |
| v2.0.0 CI build failed in `apt-get install curl` | `archive.ubuntu.com` unreachable from the GitHub runner (external mirror outage) | Removed the build-time package install; the healthcheck now uses bash `/dev/tcp`. Builds no longer depend on Ubuntu mirrors |
| `Permission denied` running scripts | Executable bit not set or not committed | `chmod +x` + `git update-index --chmod=+x` |

## 14. Production improvements

- HTTPS (section 11), an Elastic IP and a DNS name.
- Zero-downtime blue/green or rolling deploys (two app replicas behind Nginx/ALB). The current deploy replaces the container, so there is a few seconds of downtime.
- Deploy from CI (GitHub environment with approval → SSM Run Command), so nobody needs to SSH in.
- Pin base images by digest, and scan images in CI with Trivy, failing on HIGH/CRITICAL findings.
- Metrics and alerting (Prometheus + Grafana or CloudWatch alarms) with notifications to Slack or email, instead of a cron script.
- Centralised logs with a retention policy (section 9).
- An IAM role + ECR instead of a stored GHCR token.
- Keep a full release history so rollback can go back more than one step.

## 15. Known limitations

- Single EC2 instance, so no high availability. The deploy has a few seconds of downtime.
- `rollback.sh` goes back one release only; running it twice toggles between the last two. Any older tag can still be deployed with `deploy.sh <tag>`.
- Deployment state (`.deploy/`) is a local file on the host.
- The GHCR token is stored unencrypted in `~/.docker/config.json` on the host.
- HTTPS is documented but not configured, because there is no domain.
- The monitor runs from cron on the same host, so it cannot alert if the whole host is down.
- The public IP changes on instance stop/start (no Elastic IP).

## 16. Time spent

<!-- REPLACE: e.g. ~5.5 h total -->
| Activity | Time |
|---|---|
| EC2 + Docker setup | |
| Dockerfile / compose / Nginx | |
| CI pipeline + GHCR | |
| Deploy / rollback / monitor scripts | |
| Debugging CI and release issues (section 13) | |
| Evidence + README | |

## 17. AI usage disclosure

I used an AI assistant (Claude) as a guide during this assessment. It helped me:
- plan the steps;
- draft the Dockerfile, the compose file, the Nginx config, the scripts, the CI workflow and this README;
- interpret error output while debugging.

I ran every step myself on the EC2 instance. I diagnosed and fixed the issues listed in section 13. I reviewed and adjusted all the files and can explain and modify each of them.
