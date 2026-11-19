---
name: add-oidc-client
description: >-
  Registers or updates an OpenID Connect (OIDC) client in home-lab/authelia across
  clients.yaml, tracked secret placeholders, docker-compose.yml, .gitlab-ci.yml, and
  shared GitLab CI/CD variables. Use when onboarding an OIDC relying party to Authelia SSO.
---

# Onboard OIDC Client (`home-lab/authelia`)

Use Authelia's official **[OpenID Connect 1.0 Relying Party Client Integrations](https://www.authelia.com/integration/openid-connect/clients/)** directory as the primary reference for application-specific settings (`redirect_uris`, `scopes`, `claims_policy`, `token_endpoint_auth_method`, PKCE, and public vs confidential mode). When a service uses proxy SSO instead of OIDC, follow **[Traefik Proxy Integration](https://www.authelia.com/integration/proxies/traefik/)** (`forwardAuth` middleware in the consuming repository—no `clients.yaml` entry needed).

Operate strictly via stateless `git -C "<authelia_dir>"` and `glab` CLI (never SSH, probe `:2375`, print secrets, or invoke `python3`/`ruby`/`node`).

## 1. Branching, Merge Order & Role Mapping
- On persistent local checkouts (`keep_roundtrip`), capture `original_ref` first via `git -C "<authelia_dir>" symbolic-ref --short -q HEAD` (falling back to `git -C "<authelia_dir>" rev-parse HEAD` if detached) and stash any pre-existing dirty work before creating `feat/<service>-oidc` (or `chore/<service>-oidc` for updates) off latest `origin/main`:
  ```bash
  git -C "<authelia_dir>" fetch --prune origin
  git -C "<authelia_dir>" checkout -B "feat/<service>-oidc" origin/main
  ```
- **Merge Prerequisite**: `feat/<service>-oidc` MUST merge and deploy in `home-lab/authelia` **before** the consuming service deploys. Map LDAP group `"Domain Power Users"` to admin roles in the consuming application.

## 2. Client Wiring in `src/authelia-config/clients.yaml`
- Append the client under `identity_providers.oidc.clients` (`<service>` lowercase slug, `<SERVICE>` uppercase snake_case) using the upstream guide plus local conventions:
  - `client_secret: '{{ secret "/run/secrets/<SERVICE>_OAUTH_CLIENT_SECRET" }}'` (for confidential clients; rendered via Authelia's Go `template` filter—the backing GitLab variable in `home-lab/authelia` MUST store a `$pbkdf2-sha512$310000$...` or `$argon2id$...` digest rather than deprecated plaintext)
  - `authorization_policy: "two_factor"` and `consent_mode: "implicit"`
- **Authelia 4.39+ ID Token Claims (`claims_policies`)**: Authelia 4.39+ omits `email`, `name`, `groups`, and `preferred_username` from `id_token` by default (serving them from `/api/oidc/userinfo`). Whenever an app reads profile, group, or custom claims directly from `id_token`, define `identity_providers.oidc.claims_policies.<service>` and set `claims_policy: "<service>"` on the client.
- **CORS (`src/authelia-config/identity_providers.yaml`)**: `allowed_origins_from_client_redirect_uris: true` authorizes redirect origins automatically; add to `cors.allowed_origins` only for separate SPA origins.

## 3. Local 4-File Secret Plumbing & Validation
1. **Placeholder (`src/secrets/services/<SERVICE>_OAUTH_CLIENT_SECRET`)**: Write `PLACEHOLDER` so local Compose validation resolves the file path.
2. **Compose (`src/docker-compose.yml`)**: Append `"<SERVICE>_OAUTH_CLIENT_SECRET"` to `services.authelia.secrets` and add `<SERVICE>_OAUTH_CLIENT_SECRET: { file: ./secrets/services/<SERVICE>_OAUTH_CLIENT_SECRET }` under top-level `secrets:`.
3. **CI Artifact Overlay (`.gitlab-ci.yml`)**: Under `setup:generate-build-artifacts` (`# services`), append a single-quoted item:
   ```yaml
   - 'printf "%s\n" "${<SERVICE>_OAUTH_CLIENT_SECRET:?<SERVICE>_OAUTH_CLIENT_SECRET is not set}" > $BUILD_ARTIFACTS_DIR/secrets/services/<SERVICE>_OAUTH_CLIENT_SECRET'
   ```
4. **Asymmetric OIDC Secret Provisioning**: Idempotently provision `<SERVICE>_OAUTH_CLIENT_SECRET` (`masked: true`, `raw: true`, `protected: false`) via `oidc 32` mode so `home-lab/authelia` stores a `$pbkdf2-sha512$310000$...` digest while `<project_path>` stores the 64-character RFC 3986 hex plaintext:
   ```bash
   "<automations_skills_root>/implement-issue/scripts/provision-gitlab-secret.sh" oidc 32 \
     "home-lab/authelia:<SERVICE>_OAUTH_CLIENT_SECRET" \
     "<project_path>:<SERVICE>_OAUTH_CLIENT_SECRET"
   ```
5. **Validate & Open MR**: Validate modified YAML files with `yq` or `yamllint`. Commit (`feat(oidc): register <service> oidc client`), push `feat/<service>-oidc`, write `/tmp/homelab-work/mr-desc-authelia-<service>.md` via `write_file`, and open an MR via `glab mr create` passing explicit cross-repo flags:
   ```bash
   git -C "<authelia_dir>" push -u origin "feat/<service>-oidc"
   glab mr create \
     --source-branch "feat/<service>-oidc" \
     --target-branch "main" \
     --title "feat(oidc): register <service> oidc client" \
     --description-file "/tmp/homelab-work/mr-desc-authelia-<service>.md" \
     --label "type::feature" \
     --remove-source-branch \
     --yes \
     --head "https://gitlab.intranet.xbhl.online/home-lab/authelia" \
     -R "https://gitlab.intranet.xbhl.online/home-lab/authelia"
   ```
   *(Adjust branch, title, and label for `chore/<service>-oidc` updates.)* Verify CI job `test:authelia:validate-config` passes **and inspect its log trace (`glab ci trace <job_id>`) to confirm zero `option 'client_secret' is plaintext` warnings for `<service>`**, then restore `<authelia_dir>` to `<original_ref>` (popping any run-created stash) on persistent `keep_roundtrip` checkouts, `git -C "<authelia_dir>" checkout main` on `keep_cloned` checkouts, or `git -C "<authelia_dir>" checkout -f origin/main` strictly on `/tmp/homelab-work/*` caches (never run `glab mr merge`).
