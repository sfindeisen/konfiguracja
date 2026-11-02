# Security Hardening Rules for Development

Security rules for writing a multi-user, multi-role, multi-database web
application with transactional email, SMS one-time codes, 2FA,
third-party integrations and complex business logic. Most rules apply to
any web application or service.


## 0. How to use this file

### 0.1 Scope

These rules cover writing and testing code, including the CI, container
and infrastructure files in the repository. Operating the application
(hosting, DNS, provider accounts, monitoring, backups, incident response)
is out of scope. Workflow rules (commits, tests, when to ask) are in
AGENTS.md.

### 0.2 Requirement levels

- MUST / MUST NOT: mandatory. A violation blocks the merge.
- SHOULD / SHOULD NOT: the default. Deviate only with a written reason in
  the commit message, in the form `Deviation: <rule ID>: <reason>`.
- MAY: optional.

### 0.3 Rule IDs

Every rule has an ID, for example `AUTHN-04`; cite IDs in commit
messages and reviews. `AUTHN-04..07` means AUTHN-04 to AUTHN-07
inclusive.

### 0.4 Security building blocks

Each risky operation goes through one module, so that it is implemented
and reviewed once. These modules are ordinary code in this repository,
written by us; each runs inside the application or worker process that
uses it, and none of them is a separate service. If the project already
has one under another name, use that. If one is missing, add it in its
own commit before the change that needs it.

#### Request context: `RequestContext`

- What: an immutable object that the authentication middleware creates
  once per request. A background job rebuilds it from the actor ID in its
  payload (ISO-05).
- Holds: the authenticated actor (user, API key or service), its roles,
  the session ID, the client IP (HTTP-02) and the request ID.
- Used by: handlers, services and data-access functions, passed
  explicitly or through the framework's request-scoped storage.
- Never: built from request parameters, or changed after creation.

#### Data-access layer: `DataAccess`

- What: the repository or DAO modules, one set per database. They are the
  only code that imports the database driver or ORM session, opens
  connections and runs queries.
- Does: parameterized queries (INJ-01); ownership and permission filters
  taken from the request context (ISO-01); statement timeouts (DOS-02);
  maximum page sizes (DOS-03).
- Used by: service and domain code. Request handlers do not query
  databases directly.
- Enforced by: an architecture or import-lint test that fails when any
  other module imports the driver or ORM (DATA-01).

#### Policy module: `authorize(actor, action, resource)`

- What: one module holding all permission logic. `authorize()` returns
  allow or deny (or raises on deny); a companion function returns the
  query filter that list endpoints apply (AUTHZ-07).
- Used by: every handler, job and service method, before it reads or
  changes a resource.
- Reads: roles and ownership from the source of truth (DATA-11).
- Never: duplicated as inline role checks elsewhere (AUTHZ-02).

#### Outbound HTTP client: `EgressClient`

- What: a thin wrapper around the HTTP library the project already uses,
  running in the process that makes the call. It is not a proxy or a
  separate service. Operations MAY add an egress proxy on top; the code
  does not rely on one.
- Used for: every outbound HTTP request, whether to a vendor API, to a
  webhook endpoint we call, or to a URL that came from a user. Feature
  code never calls the HTTP library directly.
- Does, on every call: TLS verification (CRY-01), connect and read
  timeouts (EXT-02), a response-size limit, the retry policy (EXT-03),
  logging without secrets.
- Does, for user-supplied URLs: scheme allow-list, DNS resolution and IP
  block list, connecting to the validated IP, re-validation of every
  redirect (EXT-18..21).

#### Message sender: `MessageSender`

- What: functions such as `send_email(template, to, data)` and
  `send_sms(template, to, data)` that write a message request to an outbox
  table inside the current database transaction, plus a background worker
  that reads the outbox and calls the email or SMS provider through its
  vendor adapter (EXT-01).
- Does: renders templates with auto-escaping (MSG-03); applies rate
  limits, budgets and the suppression list (MSG-07, MSG-09, MSG-10,
  MSG-16..19); sends with an idempotency key and retries (MSG-13).
- Used by: domain code. Nothing else calls a provider SDK.

#### Audit log writer: `AuditLog`

- What: a function such as `audit(context, action, target, before, after)`
  that inserts into an audit table which the application's database user
  may insert into but not update or delete, or writes to an append-only
  log stream.
- Used for: the actions listed in LOG-07.

#### Security events: `SecurityEvent`

- What: a function such as `security_event(name, context, **fields)` that
  emits a structured log line or metric with a fixed event name, through
  the project's existing logging or metrics library. Operations build
  alerts on these names (LOG-09).

#### Configuration loader: `Config`

- What: the module that reads environment variables and the secret
  manager once at startup into a typed, read-only settings object, and
  validates it (CFG-01, CFG-02). Code reads settings only from this
  object, never from the environment directly.

#### Clock: `Clock`

- What: an injectable time source (`now()`), so that tests control time
  (BIZ-04). Domain code never reads the system clock directly.


## 1. Principles (PRIN)

- PRIN-01 Deny by default; fail closed. Missing policy, missing actor or
  an unexpected exception means deny.
- PRIN-02 Least privilege for people, services, tokens, pipelines and
  database users.
- PRIN-03 One way to do each risky thing: data access, authorization,
  egress, messaging, configuration, cryptography. Reject code that works
  around it.
- PRIN-04 Enforce in the lowest layer that can: a database constraint over
  an application check, the server over the client.
- PRIN-05 Every layer holds on its own. No layer relies on an earlier layer
  having run.
- PRIN-06 Every security decision leaves a trace (LOG).
- PRIN-07 Validate at the boundary with a schema; encode at the output for
  the target context.
- PRIN-08 Prefer maintained, well-known libraries over custom security
  code.
- PRIN-09 Treat as untrusted everything this code did not produce itself:
  request data, headers, cookies, files, vendor responses, webhooks,
  messages from other services, stored data that came from users, and AI
  model output. Data does not become trusted by being stored in our own
  database.
- PRIN-10 Users are isolated from each other by default: one user's data
  is invisible to another unless an explicit grant says otherwise (ISO).

Layer model:

```
  request
     |
     v
  [1 Edge]            size and rate limits, bot checks, headers,
                      CSRF checks, webhook signatures
  [2 Identity]        passkeys or TOTP, capped one-time codes,
                      hardened recovery, step-up re-authentication
  [3 Request context] actor and roles resolved once from the session
  [4 Authorization]   deny by default, object-level checks,
                      writable-field allow-lists, no escalation
  [5 Domain logic]    invariants, guarded state transitions,
                      idempotency keys, timeouts on vendor calls
  [6 Data layer]      one data-access layer per database, ownership
                      filters, constraints, least-privilege users
  [7 Platform/build]  secrets from a manager, safe config defaults,
                      hardened image, signed artifacts

  Cross-cutting, every layer:
    build-time gate     review, dependency checks, SAST, secret scan
    observability       structured logs, traces, audit trail, events
```

No layer trusts the one above it. If a bug skips the authorization check,
the data-access layer still scopes queries to what the actor may see, and
the database user still cannot touch other databases or change the schema.


## 2. User isolation (ISO)

Users are isolated from each other the way tenants are in a multi-tenant
system: every user's data is private to that user unless an explicit
grant says otherwise. Isolation is enforced in every layer and in every
store, cache, file, queue and channel, not only in request handlers. The
AUTHZ rules decide who may do what; these rules make sure no path skips
that decision.

### 2.1 Ownership and grants

- ISO-08 Every record of user data MUST have an explicit owner: a
  `NOT NULL` owner column, or a mandatory reference to an owned parent.
  Data without an owner is platform data, which users can at most read.
- ISO-09 Access to another user's data MUST come from an explicit grant
  (a share, a membership, a role over that object), checked by
  `authorize()`. Knowing an ID, a URL or a file name is never a grant.
- ISO-10 Write paths MUST authorize every object they reference, not only
  the one in the URL: attaching a file to a document, adding an item to an
  order, moving a record into a folder or setting a parent ID each need a
  check on the referenced object.
- ISO-11 Where data is strictly per user, foreign keys SHOULD include the
  owner, for example
  `FOREIGN KEY (owner_id, folder_id) REFERENCES folders (owner_id, id)`,
  so that the database rejects links across users.
- ISO-12 Share links are grants: at least 128 random bits, stored hashed,
  bound to one object and one permission, expiring, revocable and logged
  on use. A share link MUST NOT grant more than its creator holds
  (AUTHZ-10).
- ISO-13 Revoking a grant MUST take effect on the next request, including
  for open WebSocket subscriptions, cached results and signed URLs (keep
  their lifetime short).
- ISO-14 New data and new features are private by default. Anything
  visible to other users (public profiles, shared spaces) MUST be marked
  as such explicitly in the data model, never inferred.
- ISO-01 Data-access functions for restricted data MUST take the
  `RequestContext` and apply ownership or permission filters in the query
  itself (AUTHZ-06, AUTHZ-07).
- ISO-02 MUST return 404, not 403, for objects the actor may not see, so
  their existence is not revealed.
- ISO-03 Public identifiers SHOULD be non-sequential (UUIDv7, ULID). They
  are never an access control.

### 2.2 Stores, channels, jobs and outputs

- ISO-04 Derived stores MUST NOT bypass authorization. Search results,
  cached objects and reports are filtered by the same permission rules as
  the source; cache keys for permission-dependent content MUST include the
  actor or its permission scope.
- ISO-05 Background jobs MUST carry the actor in the payload, re-create
  the `RequestContext` and re-check authorization when they run.
- ISO-15 Every key derived from user data MUST be namespaced by its owner:
  cache keys, object-storage paths, search documents, queue messages,
  pub/sub channel names, rate-limit buckets, lock names, temporary file
  names and idempotency keys. A namespace prevents mix-ups; it is not a
  permission, and the code reading the data still checks access.
- ISO-16 Search engines MUST apply the actor's access filter inside the
  query (security trimming), so that hits, counts, facets, highlights and
  suggestions never come from data the actor may not see.
- ISO-17 Aggregates shown to users (counts, sums, rankings, "people who
  viewed this") MUST be computed only over data the actor may see;
  otherwise they reveal the existence and the values of other users'
  data.
- ISO-18 Real-time channels (WebSocket, server-sent events, pub/sub) MUST
  authorize every subscription on the server and filter every message per
  recipient. An unguessable channel name is not access control.
- ISO-19 User files MUST be stored privately (no public buckets or
  directories) and served only through short-lived signed URLs bound to
  one object (FILE-10). Temporary files MUST get random names in a private
  directory, be readable only by the process, and be deleted after use.
- ISO-20 Exports, reports and generated documents MUST be produced with
  the requesting user's permissions at generation time, and MUST be
  downloadable only by that user.
- ISO-21 Batch jobs that process many users MUST handle each user's data
  in that user's context (or in a declared system context), and MUST NOT
  mix several users' data into one output, message or file unless the
  feature is explicitly about that.
- ISO-22 Error messages, validation messages and notifications MUST NOT
  disclose another user's data: names, emails, the value behind a
  unique-constraint violation, other rows in a stack trace.

### 2.3 Requests and processes

- ISO-06 MUST NOT leak per-request state through pooled connections: no
  session-level settings or temporary tables that outlive the transaction;
  reset connection state on checkout.
- ISO-23 Request state (actor, roles, request data) MUST live in the
  request context. It MUST NOT be kept in module-level or global
  variables, class or static fields, singletons, or thread-locals that
  outlive the request: worker threads and event loops serve many users.
- ISO-24 In asynchronous code, the request context MUST travel through the
  runtime's context mechanism (for example Python `contextvars`, Node.js
  `AsyncLocalStorage`) into every task and callback the request starts,
  and MUST be cleared when the request ends. Code running outside a
  request (timers, pool callbacks) MUST NOT see a previous request's
  context.
- ISO-25 Memoization and per-process caches whose result depends on the
  actor (`lru_cache`, memoize decorators, ORM identity maps and sessions,
  GraphQL DataLoaders) MUST be created per request, or keyed by actor
  (ISO-04).
- ISO-26 Buffers and objects reused across requests (object pools,
  `sync.Pool`, reused byte arrays) MUST be cleared before reuse.
  Uninitialized allocations (for example Node.js `Buffer.allocUnsafe`)
  MUST NOT be returned to users or written to storage.

### 2.4 Platform staff

- ISO-07 Platform-staff access to user data MUST go through a separate,
  audited code path with explicit break-glass approval.


## 3. Data access and multiple databases (DATA)

### 3.1 Data access

- DATA-01 Each database MUST have exactly one data-access layer
  (`DataAccess`). Feature code MUST NOT open connections, use the database
  driver or ORM session, or build queries outside it. An architecture test
  MUST enforce this.
- DATA-03 Each database MUST be accessed with its own least-privilege
  credentials. The application user MUST NOT run DDL; migrations MUST use
  a separate user; read-only workloads SHOULD use a read-only user. A
  service MUST NOT hold credentials for databases it does not use.
- DATA-04 Database connections MUST use TLS with certificate verification
  where the database supports it, and MUST set statement timeouts
  (DOS-02).
- DATA-06 PostgreSQL row-level security MAY add a second layer for
  user-owned data. If used, the application role MUST NOT own the tables
  or have `BYPASSRLS`, and the actor MUST be set with `SET LOCAL` inside
  the transaction.

### 3.2 Several databases, one consistent state

- DATA-09 Each kind of data MUST have exactly one source of truth. Copies
  in other stores (caches, search indices, read replicas, reporting
  databases) are derived and MUST be rebuildable from it.
- DATA-11 Security decisions (session validity and revocation, roles and
  permissions, one-time-code use, balances) MUST read the source of truth,
  never a lagging replica or a long-lived cache.
- DATA-12 MUST NOT use distributed transactions across databases. Use the
  transactional outbox and idempotent consumers (BIZ-10, BIZ-14).
- DATA-13 References between databases cannot use foreign keys. The code
  MUST validate them on write, and reconciliation jobs MUST detect orphans
  and drift (BIZ-12).
- DATA-14 Migrations MUST be backward compatible (expand, migrate,
  contract), so the app runs against schema N and N-1. Each database
  tracks its own schema version; the migrator MUST be idempotent and MUST
  report drift as an error.
- DATA-15 Identifiers that travel between databases SHOULD be globally
  unique (UUIDs), so records from different stores cannot be confused.
- DATA-16 Deleting data MUST reach every store that holds a copy
  (PRIV-03).


## 4. Identity and authentication (AUTHN)

### 4.1 General

- AUTHN-01 MUST use a maintained authentication library or identity
  provider. MUST NOT implement password hashing, OTP generation, session
  handling or token cryptography by hand.
- AUTHN-02 MUST NOT ship default, sample or hard-coded credentials for any
  role or environment.

### 4.2 Passwords

- AUTHN-03 MUST hash passwords with Argon2id (preferred), scrypt or bcrypt
  at a tuned cost. bcrypt ignores input beyond 72 bytes; if bcrypt is used,
  MUST handle longer input consistently (pre-hash or reject). SHOULD add a
  pepper held outside the database.
- AUTHN-04 MUST follow NIST SP 800-63B-4 section 3.1.1.2: minimum 15
  characters when the password is the only factor, minimum 8 when MFA is
  always required; allow at least 64 characters; accept printable ASCII,
  space and Unicode (count code points); check new passwords against a
  list of breached and common passwords. MUST NOT impose composition
  rules, periodic rotation, security questions or password hints. MUST
  allow paste and password managers.
- AUTHN-05 MUST cap raw password input length (for example 1024 bytes) to
  bound hashing cost.
- AUTHN-06 MUST apply rate limiting before computing a password hash.

### 4.3 Brute force and enumeration

- AUTHN-07 MUST throttle login, signup, password reset and OTP
  verification per account and per client IP (the trusted client IP,
  HTTP-02), with progressive delays. MUST NOT implement hard lockouts that
  an attacker can trigger against a victim.
- AUTHN-08 MUST count attempts per authentication operation, not per HTTP
  request. GraphQL aliases and batch endpoints can carry many guesses in
  one request.
- AUTHN-09 MUST return identical responses with comparable timing for
  existing and non-existing accounts in login, signup, reset and
  invitation flows.
- AUTHN-10 SHOULD apply bot detection on unauthenticated flows that cost
  money or send messages.

### 4.4 Second factors and one-time codes

- AUTHN-11 MUST support passkeys (WebAuthn) and SHOULD make them the
  default second factor. MUST allow several passkeys per user.
- AUTHN-12 TOTP: secrets MUST be encrypted at rest (CRY-04); accept at
  most one time step of clock skew; MUST reject reuse of a code within its
  validity window.
- AUTHN-13 SMS and voice codes are a fallback only. NIST SP 800-63B-4
  classifies PSTN delivery as a restricted authenticator. The app MUST
  offer a phishing-resistant option.
- AUTHN-14 Every one-time code (SMS, email, step-up) MUST come from a
  CSPRNG, have at least 6 digits, be stored hashed, be single use, expire
  within 10 minutes, and be compared in constant time.
- AUTHN-15 Every one-time code MUST be bound to user, purpose (for example
  `login`, `change_phone`, `confirm_payout`) and session. A code issued for
  one purpose MUST NOT be accepted for another.
- AUTHN-16 MUST invalidate a code after at most 5 failed attempts, and
  MUST throttle resends with increasing delays.
- AUTHN-17 Recovery codes MUST be single use, stored hashed, shown once,
  and regenerable only after re-authentication.
- AUTHN-18 A phone number or email address MUST be verified before it can
  serve as a factor or a recovery channel. Phone numbers MUST be stored in
  E.164 format.

### 4.5 Recovery and sensitive changes

- AUTHN-19 Password-reset tokens MUST have at least 128 bits of entropy,
  be stored hashed, be single use, expire within 15 to 60 minutes, and be
  invalidated by any password change.
- AUTHN-20 Links sent by email or SMS MUST be built from configured base
  URLs, never from `Host` or `X-Forwarded-Host`.
- AUTHN-21 A password reset MUST NOT bypass MFA. Resetting MFA MUST
  require stronger proof, apply a cooling-off delay, and notify every
  existing channel.
- AUTHN-22 MUST require step-up re-authentication before changing email,
  phone, password, MFA, payout details or API keys, and before granting
  admin roles. MUST notify the previous address or number with a way to
  report or undo the change.

### 4.6 Sessions and tokens

- AUTHN-23 Session cookies MUST be `__Host-` prefixed (no `Domain`
  attribute, so they are never sent to other subdomains), `Secure`,
  `HttpOnly`, and `SameSite=Lax` or `Strict`. Session IDs MUST NOT appear
  in URLs.
- AUTHN-24 MUST rotate the session ID on login and on privilege change.
- AUTHN-25 MUST implement idle and absolute session timeouts. Logout MUST
  invalidate the server-side session. Password and MFA resets MUST revoke
  all sessions. Users SHOULD be able to list and revoke their sessions.
- AUTHN-26 If JWTs are used: MUST pin the accepted algorithm and reject
  `none`; MUST validate `iss`, `aud`, `exp`, `nbf` and scope; access tokens
  MUST be short-lived; claims MUST NOT contain secrets; revocation MUST be
  possible; tokens MUST NOT be stored in `localStorage` or
  `sessionStorage`.

### 4.7 SSO and federation

- AUTHN-27 OIDC and OAuth: MUST use `state` and `nonce`, PKCE and
  exact-match redirect URIs, and MUST validate signature, issuer and
  audience. SAML: MUST validate the assertion signature, audience,
  recipient and validity window, and MUST parse with DTDs disabled
  (PARSE-01).
- AUTHN-28 MUST NOT link or create accounts by email from an external
  identity provider unless the email is verified and that provider is
  configured as authoritative for the email's domain.

### 4.8 Invitations and account lifecycle

- AUTHN-29 Invitation tokens MUST be random, stored hashed, single use,
  expiring, and bound to the invited email. The role MUST come
  from the stored invitation, never from the accept request.
- AUTHN-30 Accepting an invitation while signed in with a different email
  MUST require explicit confirmation.
- AUTHN-31 Deactivating or deleting an account MUST immediately revoke its
  sessions, API keys and scheduled jobs. Removing a role MUST take effect
  on the next request (DATA-11).
- AUTHN-32 Uniqueness of emails and usernames MUST be checked on a
  normalized form (Unicode NFKC plus case folding). Mail MUST be sent to
  the address as entered. Usernames shown to others SHOULD reject
  mixed-script and confusable characters.

### 4.9 API keys, machine identities and back office

- AUTHN-33 API keys MUST be scoped to one account and an explicit
  permission set, MUST expire, MUST be stored hashed and shown once, MUST
  carry a recognizable prefix (for example `acme_live_`) so secret
  scanners detect leaks, and MUST record last use.
- AUTHN-34 Service-to-service calls MUST be authenticated (mTLS or signed
  short-lived tokens) and authorized. Network location is never proof of
  identity.
- AUTHN-35 The platform back office MUST be a separate application or
  route group with its own authentication, phishing-resistant MFA and
  audit trail, and MUST NOT be reachable with a regular user session.
- AUTHN-36 Support impersonation ("log in as") MUST be explicit,
  time-boxed, audited and visibly bannered, and MUST NOT allow changing
  credentials, MFA or payout details.
- AUTHN-37 MUST compare secrets (tokens, codes, HMACs, API keys) in
  constant time.


## 5. Authorization (AUTHZ)

- AUTHZ-01 Permissions MUST be verbs on resources (`invoice.read`,
  `invoice.approve`). Roles are named bundles of permissions. A user MAY
  hold several roles; role assignments are explicit records.
- AUTHZ-02 Code MUST check permissions through
  `authorize(actor, permission, resource)`, never by comparing role names.
- AUTHZ-03 There MUST be exactly one policy module. A policy engine (OPA,
  Cedar, OpenFGA) MAY replace plain functions only when relationship rules
  require it.
- AUTHZ-04 Platform-staff roles MUST be separate from regular user roles.
  No superadmin flag in the users table.
- AUTHZ-05 Every route, GraphQL field or resolver, RPC method, WebSocket
  message type and job handler MUST declare a policy; anything undeclared
  MUST be denied. An architecture test MUST enumerate handlers and fail CI
  for any handler without a policy.
- AUTHZ-06 MUST perform object-level checks: load the object, then
  authorize the actor against that object (prevents IDOR/BOLA). Never
  assume an ID came from a page the user could see.
- AUTHZ-07 List endpoints MUST filter in the query, not in memory after
  fetching, so pagination and counts do not leak.
- AUTHZ-08 MUST map requests to explicit input DTOs with an allow-list of
  writable fields per role. Fields such as `role`, `owner_id`,
  `account_id`, `price`, `status` and `email_verified` MUST NOT be bindable
  from request bodies unless a specific permission allows it (mass
  assignment).
- AUTHZ-09 Responses MUST be built from response DTOs, never by
  serializing ORM entities.
- AUTHZ-10 An actor MUST NOT grant a permission it does not hold. Role
  changes MUST require step-up (AUTHN-22), and MUST be audited and
  notified. The last admin MUST NOT be able to remove their own admin
  role.
- AUTHZ-11 Money movements and approvals MUST enforce separation of
  duties: the creator of a payment, refund or price change MUST NOT
  approve it.
- AUTHZ-12 Client-side checks are UX only; the server decides.
- AUTHZ-13 MUST also authorize in: background jobs; scheduled reports;
  exports; search and autocomplete; aggregates and dashboards; file
  downloads (signed URLs issued only after the check, short TTL);
  WebSocket subscriptions; GraphQL nested resolvers; bulk operations
  (every object, not just the first); notifications and emails (no
  content the recipient cannot open in the app); admin, debug and
  unlinked routes (forced browsing).
- AUTHZ-14 Cached permission decisions MUST have a short TTL and MUST be
  invalidated on role change.
- AUTHZ-15 File names and paths MUST NOT come from user input; resolve IDs
  to storage keys (path traversal).
- AUTHZ-16 MUST keep an authorization matrix (role x action x ownership)
  as test data and generate one test per cell, including the "another
  user's object" and "no role" cases (TEST-03).


## 6. Transactional email and SMS (MSG)

### 6.1 Email

- MSG-01 MUST send all email and SMS through `MessageSender` via the
  outbox (MSG-13).
- MSG-02 Users MUST NOT control the `From` address. Messages sent on a
  user's behalf (invitations, shares) go out from the app's domain; the
  user's name MAY appear in the display name, sanitized, and their address
  MAY be used as `Reply-To`.
- MSG-03 Templates MUST auto-escape every variable; no raw user HTML; CR
  and LF MUST be stripped from every value that reaches a header; every
  message MUST include a plain-text part. User text MUST NOT be compiled
  as a template.
- MSG-04 Links MUST be built from the configured base URL (AUTHN-20).
- MSG-05 Confirmation and magic links MUST NOT perform the action on GET.
  They open a page that performs it on POST, because mail scanners
  prefetch links.
- MSG-06 Emails SHOULD NOT contain sensitive data; link to the app
  instead.
- MSG-07 Invitations, shares and notifications MUST limit free text and
  MUST be rate-limited per sender and per recipient.
- MSG-08 MUST process bounce and complaint webhooks and maintain a
  suppression list; MUST stop sending to hard-bounced addresses.

### 6.2 SMS

- MSG-09 MUST implement SMS pumping controls in code:
  - a destination-country allow-list;
  - rate limits per number, number prefix, client IP, device and account,
    with increasing delays between resends;
  - bot detection before the first send on unauthenticated flows;
  - line-type lookup (send to mobile numbers only) where available;
  - a verify-rate metric (codes verified / codes sent) per country,
    emitted as a `SecurityEvent`.
- MSG-10 MUST enforce an SMS budget in the app, globally and per account:
  a counter that stops sending and emits a `SecurityEvent` when exceeded,
  independent of any provider limit.
- MSG-11 SMS text MUST be short and MUST NOT put links next to codes. It
  SHOULD end with the origin-bound line `@app.example.com #123456` for
  WebOTP autofill.
- MSG-12 MUST NOT treat a phone number as a permanent identity; numbers
  are recycled. Re-verify before high-risk use.

### 6.3 Delivery pipeline

- MSG-13 The message request MUST be written to an outbox table in the
  same transaction as the business change. A worker sends it with an
  idempotency key per message, retries with exponential backoff and jitter
  on timeouts and 5xx responses, moves it to a dead-letter queue after N
  attempts, and records the provider message ID and delivery status.
- MSG-14 Non-production environments MUST route email and SMS to a sink,
  with an explicit allow-list of test recipients.

### 6.4 Sign-up and verification messages

Anyone can type someone else's email address or phone number into a
sign-up form, and repeat it every time the pending sign-up expires. These
rules protect the owner of that address and stop the form from being
used to deliver spam.

- MSG-15 A sign-up MUST stay pending until its email address or phone
  number is verified. A pending sign-up MUST NOT receive any message other
  than the verification message, MUST NOT be visible to other users, and
  MUST expire (for example after 24 hours).
- MSG-16 Verification messages MUST be rate-limited per destination,
  independently of IP, session and device, with growing intervals (for
  example at most 3 per 24 hours and 5 per 30 days). These counters MUST
  outlive the pending sign-up, so that expiring and retrying does not
  reset them.
- MSG-17 Limits and suppression MUST be keyed on a delivery key, not on the
  address as typed: lowercase, without a `+tag`, and without dots for
  providers that ignore them (such as gmail.com); phone numbers in E.164.
  Store an HMAC of the key, not the address. Also limit verification
  messages per recipient domain.
- MSG-18 Every verification email MUST carry a "This wasn't me" link that
  works without signing in. It opens a page whose POST button (MSG-05)
  cancels the pending sign-up and puts the delivery key on a sign-up
  suppression list. The same action MAY be offered through the
  `List-Unsubscribe` and `List-Unsubscribe-Post` headers.
- MSG-19 For a suppressed delivery key, sign-up and resend requests MUST
  send nothing, and the response MUST look exactly as if a message had
  been sent (AUTHN-09). Spam complaints and hard bounces on verification
  messages MUST suppress the key as well (MSG-08).
- MSG-20 Suppression MUST be lifted only on proof of control of the
  address: for example an unblock link the owner explicitly requests,
  limited to one message per delivery key per 30 days.
- MSG-21 Verification and invitation messages MUST NOT contain text the
  requester typed (name, company, comment); sign-up forms are a known
  channel for delivering spam and phishing text under the app's name.
  Greet users by name only after verification.
- MSG-22 If the address already belongs to an account, MUST NOT send a new
  verification link. At most one "someone tried to sign up with your
  address" notice per period MAY be sent instead; the response stays
  identical (AUTHN-09).
- MSG-23 Phone numbers get the same per-destination limits and
  suppression (MSG-16..19). An inbound `STOP` reply, where the provider
  supports it, MUST suppress the number. An unauthenticated visitor SHOULD
  NOT be able to trigger an SMS at all: verify the email address first, or
  put the SMS step behind bot detection (MSG-09).
- MSG-24 Limit hits and attempts on suppressed keys MUST emit
  `SecurityEvent`s.


## 7. Third-party systems (EXT)

### 7.1 Outbound calls

- EXT-01 Each vendor MUST be wrapped in exactly one adapter. Domain code
  MUST NOT use vendor SDK types.
- EXT-02 Every outbound call MUST set connect and read timeouts.
- EXT-03 Retries are allowed only for idempotent operations, with
  exponential backoff, jitter and a cap. Non-idempotent calls MUST carry an
  idempotency key.
- EXT-04 SHOULD isolate vendors with separate worker or connection pools
  (bulkheads) and circuit breakers.
- EXT-05 MUST NOT make network calls inside a database transaction. Use
  the outbox (BIZ-14).
- EXT-06 MUST validate vendor responses against a schema, with size
  limits. Vendor data is untrusted input.
- EXT-07 MUST honor `429` responses and `Retry-After`.
- EXT-08 MUST define degraded behavior per integration: queue and retry,
  fallback provider, or a visible "temporarily unavailable".
- EXT-09 MUST send vendors only the fields they need, request the
  narrowest scopes, and store per-user OAuth tokens encrypted (CRY-04)
  and revocable.
- EXT-10 Vendor SDKs are dependencies (AI-01). Their telemetry SHOULD be
  disabled unless needed.
- EXT-11 Card data MUST NOT touch the application's servers. Use the
  payment provider's hosted fields or redirect, and store only provider
  tokens.

### 7.2 Inbound webhooks

- EXT-12 MUST verify the signature (usually an HMAC over the raw body) in
  constant time with a per-vendor secret, before parsing the payload.
- EXT-13 MUST reject stale timestamps (for example older than 5 minutes)
  and MUST deduplicate by event ID.
- EXT-14 MUST store the event and acknowledge quickly; process it
  asynchronously.
- EXT-15 MUST map the vendor's customer or account ID to an internal
  account through a stored mapping, never through an internal ID taken
  from the payload.
- EXT-16 For state that matters (payment succeeded, document signed) MUST
  re-fetch the object from the vendor's API by ID before acting.

### 7.3 User-controlled URLs (SSRF)

- EXT-17 Every request to a user-supplied URL (webhook targets, URL
  imports, avatar fetches, link previews, renderers) MUST go through
  `EgressClient`.
- EXT-18 `EgressClient` MUST allow only `https` (`http` only where
  unavoidable) and reject every other scheme (`file`, `gopher`, `ftp`,
  `data`, ...).
- EXT-19 `EgressClient` MUST resolve DNS and block private, loopback,
  link-local, unique-local, multicast, broadcast and cloud metadata
  addresses (for example `169.254.169.254`, `fd00:ec2::254`), including
  IPv4-mapped IPv6 and alternative IP spellings (decimal, octal,
  hexadecimal).
- EXT-20 `EgressClient` MUST connect to the IP it validated (defeats DNS
  rebinding) and MUST re-validate every redirect hop, or disable
  redirects.
- EXT-21 `EgressClient` MUST enforce timeouts and a response-size limit,
  and MUST NOT forward internal credentials or cookies.
- EXT-22 HTML-to-PDF converters, headless browsers, image fetchers and
  link-preview generators MUST run in an isolated worker, with local file
  access and script execution disabled where possible. Their network
  access MUST follow EXT-18..21.
- EXT-23 MUST NOT return the raw response of a user-supplied URL to the
  user.
- EXT-24 Outbound webhooks sent to user-configured endpoints MUST be
  signed, timestamped, retried with backoff, and logged per delivery.
- EXT-25 The repo MUST contain the list of hosts the app legitimately
  calls (egress allow-list), so operations can enforce it.

## 8. Business logic and data integrity (BIZ)

### 8.1 Invariants and types

- BIZ-01 Each aggregate MUST document its invariants next to its code.
- BIZ-02 Invariants MUST be enforced by database constraints wherever
  expressible: `NOT NULL`, `CHECK`, `UNIQUE` (including partial unique
  indexes), foreign keys, and exclusion constraints for overlapping time
  ranges.
- BIZ-03 Money MUST use integer minor units or a decimal type, always with
  an explicit currency. MUST NOT use binary floating point. The rounding
  mode and the points where rounding happens MUST be defined.
- BIZ-04 Instants MUST be stored in UTC (`timestamptz`). Business dates
  (due date, billing day) MUST be stored as dates, together with the time
  zone they refer to. Time MUST come from the injectable `Clock`. DST
  transitions MUST be tested.
- BIZ-05 Every input MUST have bounds: numeric ranges, string lengths,
  list sizes, page sizes, file sizes. MUST check overflow against column
  types. Integers above 2^53 and monetary amounts MUST be sent as strings
  in JSON.
- BIZ-06 Validation MUST happen at the edge (schema) and in the domain
  (business rules). Client-side validation is UX only.

### 8.2 State machines and concurrency

- BIZ-07 State changes MUST go through one transition function per
  aggregate that validates the transition and writes it with a guard:

```sql
UPDATE invoices
   SET status = 'approved', approved_by = :actor, version = version + 1
 WHERE id = :id
   AND status = 'pending' AND version = :version;
-- 0 rows affected: invalid transition or concurrent change.
-- Reload and report; do not retry blindly.
```

- BIZ-08 Check-then-act sequences MUST be atomic: a guarded update,
  `SELECT ... FOR UPDATE`, an optimistic version column, or a unique
  constraint. Counters MUST use atomic increments.
- BIZ-09 Mutating endpoints that clients may retry MUST accept an
  `Idempotency-Key`, store key, request hash and response, replay the
  stored response, and reject reuse of a key with a different request.
- BIZ-10 Queue consumers MUST be idempotent; delivery is at-least-once.
- BIZ-11 Multi-step flows across services or databases MUST use sagas
  with compensating actions.
- BIZ-12 Data mirrored with vendors (payments, subscriptions) MUST have
  reconciliation jobs that detect and report drift.

### 8.3 Errors

- BIZ-13 Errors MUST fail closed. An exception in authentication,
  authorization, validation or policy evaluation results in deny. No
  catch-all that logs and continues. The whole unit of work MUST roll
  back.
- BIZ-14 Every side effect that must follow a commit (messages, events,
  vendor calls) MUST go through the transactional outbox.
- BIZ-15 Clients MUST receive generic error messages with a correlation
  ID; details go to logs only.
- BIZ-16 MUST release every resource (connection, file handle, lock,
  temporary file) on all error paths (`try/finally`, context managers,
  `defer`).
- BIZ-17 MUST check return values and handle missing parameters
  explicitly. No implicit default that grants access or skips a check.

### 8.4 Misuse cases and abuse

- BIZ-18 Every feature MUST list its misuse cases (called twice, out of
  order, concurrently, with negative or huge values, by the wrong role, on
  another user's object, after cancellation, with an old token, at high
  rate) and cover each with a test or a limit.
- BIZ-19 Risky new logic SHOULD ship behind a feature flag usable as a
  kill switch.
- BIZ-20 Business flows open to automation (signup, booking, purchasing,
  coupons, invitations, voting) MUST have per-account limits and
  plausibility checks against bulk abuse and scalping bots.

### 8.5 Imports, exports and bulk operations

- BIZ-21 Imports MUST validate every row with the same domain validation
  as the API, enforce file-size, row-count and field-length limits, run
  asynchronously with per-user quotas, and report partial failure
  explicitly (all-or-nothing, or a per-row result file).
- BIZ-22 Exports MUST be authorized per row, run asynchronously when
  large, and be delivered through short-lived signed links, never as email
  attachments.


## 9. AI-generated code (AI)

- AI-01 Dependency gate. Every new dependency (including vendor SDKs and
  new transitive packages) MUST:
  - have a reason in the commit message;
  - resolve from the official registry (or the project's registry proxy,
    if there is one);
  - be checked for existence, publisher history, package age (flag
    packages younger than 90 days), maintenance status and license;
  - be installed from a lockfile with integrity hashes.
  Never install a package only because an AI tool suggested it. AI tools
  invent plausible package names, and attackers register them
  ("slopsquatting").
- AI-02 Changes to authentication, authorization, data access,
  cryptography, payments, migrations or CI configuration MUST say so in
  the commit message, so that a human reviews them closely.
- AI-03 Generated code MUST reuse the building blocks in section 0.4.
  Duplicating a permission check, a data-access path or an HTTP client is
  a defect.
- AI-04 Before committing, check generated code for: string-built SQL or
  commands; missing authorization; disabled TLS verification; wildcard
  CORS with credentials; weak cryptography (MD5, SHA-1, ECB, static IVs);
  JWT `alg: none`; swallowed exceptions and fail-open defaults; deprecated
  APIs; configuration keys, library functions or vendor endpoints that do
  not exist; tests that only restate the implementation.
- AI-05 Tests MUST be derived from the specification, not from the
  implementation. Core domain logic SHOULD also have property-based tests.
- AI-06 If the product calls an LLM at runtime, the OWASP Top 10 for LLM
  Applications applies as well. Model output is untrusted input: validate
  and encode it, never execute it.

## 10. Injection and output encoding (INJ)

- INJ-01 MUST use parameterized queries or safe ORM APIs for every query.
  MUST NOT concatenate or interpolate untrusted data into SQL, HQL/JPQL,
  NoSQL queries, LDAP filters, XPath expressions or search-engine query
  strings.
- INJ-02 Dynamic identifiers (table, column, sort field, sort direction)
  MUST come from an allow-list mapping, never from raw input.
- INJ-03 Raw SQL fragments in ORMs (`raw()`, `extra()`, `literal()` and
  similar) MUST NOT contain untrusted data.
- INJ-04 MUST type-check inputs before NoSQL queries, so objects cannot
  inject operators (for example `{"$ne": null}` or `$where`).
- INJ-05 MUST NOT invoke a shell with untrusted input. Use argument arrays
  without a shell, put `--` before user-supplied arguments, and allow-list
  values where possible.
- INJ-06 MUST NOT evaluate untrusted input as code, template or expression
  (`eval`, `exec`, `Function`, template compilation, EL/OGNL/SpEL,
  server-side template engines).
- INJ-07 MUST rely on the framework's context-aware auto-escaping for
  HTML. Every bypass (`dangerouslySetInnerHTML`, `v-html`, `|safe`,
  `raw()`) MUST carry a review comment and use sanitized input (INJ-08).
- INJ-08 Rich text MUST be sanitized server-side with a maintained
  allow-list sanitizer. Markdown MUST be rendered with raw HTML disabled,
  then sanitized.
- INJ-09 Values placed into HTML attributes, URLs, JavaScript, CSS or
  JSON embedded in HTML MUST use the encoder for that context.
- INJ-10 Headers, cookies and redirect locations MUST be set through
  framework APIs; raw CR and LF MUST be rejected (response splitting).
- INJ-11 Logs MUST be structured, with untrusted values encoded (log
  injection).
- INJ-12 CSV and spreadsheet exports MUST neutralize cells that begin with
  `=`, `+`, `-`, `@`, tab or carriage return (formula injection).


## 11. Browser security, CSRF and front-end code (WEB)

### 11.1 Headers and cookies

- WEB-01 MUST send a Content-Security-Policy with nonce- or hash-based
  scripts and `'strict-dynamic'`, no `'unsafe-inline'` or `'unsafe-eval'`
  for scripts, `object-src 'none'`, `base-uri 'none'` (or `'self'`), and
  `frame-ancestors 'none'` (or an explicit allow-list for embedding;
  prevents clickjacking). SHOULD collect violation reports.
- WEB-02 MUST send `Strict-Transport-Security: max-age=31536000;
  includeSubDomains`.
- WEB-03 MUST send `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: strict-origin-when-cross-origin`, and a
  `Permissions-Policy` that denies unused features.
- WEB-04 Session cookies MUST follow AUTHN-23. Other cookies MUST set
  `Secure` and the narrowest `Path` and `SameSite` possible.
- WEB-05 CORS MUST use an explicit origin allow-list, MUST NOT reflect the
  request `Origin`, and MUST NOT combine wildcard origins with
  credentials.
- WEB-06 Authenticated and user-specific responses MUST send
  `Cache-Control: private, no-store` unless explicitly designed for private
  caching, and MUST NOT be cacheable by shared caches. Caching rules MUST
  NOT key on path patterns alone (web cache deception).

### 11.2 Cross-site request forgery (CSRF)

- WEB-07 Every cookie-authenticated, state-changing request MUST be
  protected by a session-bound synchronizer token, or by a strict `Origin`
  check (falling back to `Sec-Fetch-Site`) against an allow-list.
  `SameSite` alone is NOT sufficient: every subdomain of the site counts
  as same-site (a compromised or user-content subdomain included), and
  `Lax` still sends cookies on top-level GET navigations.
- WEB-08 GET, HEAD and OPTIONS MUST NOT change state.
- WEB-09 JSON APIs MUST accept only `application/json` (or the documented
  content types) and reject form encodings.
- WEB-10 Login forms and SSO callbacks MUST be CSRF-protected (login CSRF;
  OAuth `state`).
- WEB-11 WebSocket upgrades MUST check `Origin` against an allow-list and
  authenticate the connection (cross-site WebSocket hijacking). Each
  message type MUST be authorized (AUTHZ-05).
- WEB-12 CORS MUST NOT be treated as a CSRF defense; it governs reading
  responses, not sending requests.

### 11.3 Front-end code

- WEB-13 MUST NOT pass untrusted data to DOM sinks: `innerHTML`,
  `outerHTML`, `insertAdjacentHTML`, `document.write`, `eval`,
  `new Function`, string arguments to `setTimeout`/`setInterval`, or
  `location` assignments with untrusted URLs. SHOULD enable Trusted Types
  where the framework supports it.
- WEB-14 User-supplied links MUST allow only the `https:`, `http:` and
  `mailto:` schemes (blocks `javascript:` URLs).
- WEB-15 `postMessage` calls MUST name an explicit target origin. Message
  handlers MUST check `event.origin` against an allow-list and validate the
  payload.
- WEB-16 MUST NOT deep-merge or assign untrusted objects into plain
  objects. MUST drop `__proto__`, `constructor` and `prototype` keys.
  SHOULD use `Map` or `Object.create(null)` for dictionaries. Applies to
  the browser and to Node.js (prototype pollution).
- WEB-17 Third-party scripts (analytics, chat widgets) MUST NOT load on
  authentication, payment or admin pages. Every third-party origin MUST be
  listed in the CSP. Static third-party assets MUST use Subresource
  Integrity.
- WEB-18 Session tokens MUST stay in `HttpOnly` cookies. Secrets and
  tokens MUST NOT be stored in `localStorage`, `sessionStorage`, IndexedDB
  or URLs.
- WEB-19 Production builds MUST NOT expose source maps publicly, debug
  flags, or dev-only routes and tools.
- WEB-20 Links with `target="_blank"` SHOULD use
  `rel="noopener noreferrer"`. OTP inputs SHOULD use
  `autocomplete="one-time-code"`.
- WEB-21 MUST clear client-side caches and state of the previous user on
  logout and on account switch.


## 12. API design (API)

- API-01 Every request MUST be validated against a schema (OpenAPI, JSON
  Schema or typed DTOs). Unknown fields MUST be rejected.
- API-02 Responses SHOULD be validated against the schema in tests.
- API-03 Limits MUST exist for body size, array length, nesting depth,
  string length, page size and query time (DOS-01..03).
- API-04 GraphQL MUST enforce depth, cost, alias and batch limits.
  Introspection SHOULD be disabled for public production clients, which
  SHOULD use persisted queries.
- API-05 Rate limits MUST exist per user, per account and per client IP,
  stricter for unauthenticated and expensive endpoints (DOS-05).
- API-06 Errors MUST use one format, without stack traces, SQL, file
  paths, internal hostnames or library versions.
- API-07 Redirect targets (`next`, `return_to`, `redirect_uri`) MUST be
  relative paths or match an allow-list exactly (open redirect).
- API-08 Duplicate query parameters and duplicate JSON keys MUST be
  rejected, or handled by one documented rule in every layer (parameter
  pollution).
- API-09 Deprecated API versions MUST keep every security control until
  they are removed.
- API-10 Every endpoint MUST appear in the API specification. Undocumented
  ("shadow") endpoints MUST NOT exist.


## 13. Files and uploads (FILE)

- FILE-01 Uploads MUST have size limits, per file and as a per-user quota.
- FILE-02 The file type MUST be detected from content (magic bytes) and
  checked against an allow-list. Extensions and `Content-Type` headers are
  not trusted.
- FILE-03 Files MUST be stored in object storage under random keys, never
  on paths built from user input and never inside a web root.
- FILE-04 User files MUST be served from a separate registrable domain
  (for example `example-usercontent.com`, never a subdomain of the app's
  domain), with `Content-Disposition: attachment` for everything except
  allow-listed image types, and with `X-Content-Type-Options: nosniff`.
- FILE-05 SVG MUST be served as an attachment, or rasterized or sanitized
  first. Uploaded HTML MUST never be served inline.
- FILE-06 Image metadata (EXIF, GPS) MUST be stripped.
- FILE-07 Uploads SHOULD be malware-scanned before other users can access
  them.
- FILE-08 Image, PDF and office-document processing MUST run in an
  isolated worker with CPU, memory and time limits.
- FILE-09 Archive extraction MUST reject absolute paths, `..` segments and
  symlinks (zip slip), and MUST enforce limits on entry count, total size
  and compression ratio.
- FILE-10 Download URLs MUST be short-lived signed URLs, issued after
  authorization (AUTHZ-13).


## 14. Cryptography (CRY)

- CRY-01 All traffic, internal included, MUST use TLS 1.2 or higher.
  Outbound clients MUST verify certificates and hostnames; production
  configuration MUST NOT be able to disable verification.
- CRY-02 MUST use high-level libraries (libsodium, Tink, or the platform's
  vetted equivalent). MUST NOT implement cryptographic primitives or
  protocols.
- CRY-03 Symmetric encryption MUST be authenticated (AES-GCM,
  ChaCha20-Poly1305). MUST NOT use MD5 or SHA-1 for security, ECB,
  unauthenticated CBC, RC4, DES or PKCS#1 v1.5 encryption. A nonce MUST
  NOT be reused with the same key.
- CRY-04 Sensitive fields (OAuth tokens, TOTP secrets, IBANs, ID numbers)
  MUST use envelope encryption with keys from a KMS. Per-user data keys
  MAY be used to allow crypto-shredding on account deletion. Ciphertext
  MUST record its key ID so keys can rotate.
- CRY-05 Keys and secrets MUST NOT appear in code or committed
  configuration.
- CRY-06 Randomness for security purposes MUST come from the OS CSPRNG
  (for example Python `secrets`, Node.js `crypto.randomBytes`). MUST NOT
  use `Math.random`, `random` or time-seeded generators.
- CRY-07 Tokens, API keys and recovery codes MUST be stored hashed. A
  fast hash such as SHA-256 is acceptable for high-entropy random tokens;
  passwords follow AUTHN-03.
- CRY-08 Algorithm choices MUST live in one module (crypto agility), so a
  migration to post-quantum algorithms is a contained change.
- CRY-09 HMAC and signature checks MUST be constant-time and MUST happen
  before parsing or acting on the payload.


## 15. Parsers, serialization and HTTP-level traps (PARSE, HTTP)

### 15.1 Parsers and serialization

- PARSE-01 XML parsers MUST disable DTDs, external entities and entity
  expansion (XXE, billion laughs). This includes SVG, DOCX, XLSX, SAML and
  XML-based APIs.
- PARSE-02 YAML MUST be loaded with safe loaders only.
- PARSE-03 MUST NOT deserialize untrusted data with native object formats
  (`pickle`, Java serialization, PHP `unserialize`, .NET
  `BinaryFormatter`, Ruby `Marshal`). Use JSON plus a schema. Client-held
  state MUST be signed or encrypted, and verified on every use.
- PARSE-04 MUST NOT compile user-supplied regular expressions. Patterns
  applied to user input MUST avoid nested or overlapping quantifiers
  (ReDoS), MUST run on length-limited input, and SHOULD use a linear-time
  engine such as RE2.
- PARSE-05 Input MUST be parsed once, at the edge, with a strict schema;
  raw strings MUST NOT be re-parsed deeper in the stack.
- PARSE-06 Numeric parsing MUST reject values outside expected ranges,
  including huge literals, `NaN` and `Infinity`.

### 15.2 HTTP-level traps and exposed internals

- HTTP-01 The app MUST accept only an allow-list of `Host` values and MUST
  NOT build absolute URLs from `Host` or `X-Forwarded-Host`.
- HTTP-02 The client IP MUST be taken from `X-Forwarded-For` only for a
  configured number of trusted proxy hops; otherwise from the socket. Rate
  limits and audit records MUST use this derived IP.
- HTTP-03 MUST NOT implement custom HTTP parsing. Requests carrying both
  `Content-Length` and `Transfer-Encoding` MUST be rejected (request
  smuggling).
- HTTP-04 Production builds MUST disable framework debug pages,
  interactive consoles, GraphQL IDEs, unauthenticated metrics and verbose
  health details, and MUST NOT serve directory listings or `.git`, `.env`,
  backup or temporary files.
- HTTP-05 Responses that vary by user MUST NOT be cacheable by shared
  caches (WEB-06). Unkeyed request headers MUST NOT influence cacheable
  responses (cache poisoning).


## 16. Denial of service at the application level (DOS)

Volumetric DDoS is absorbed in front of the app and is out of scope. The
code decides whether one cheap request can trigger expensive work.

### 16.1 Bound every request

- DOS-01 MUST set limits in the framework, before parsing: body size,
  header size, JSON depth, array length, number of multipart parts, upload
  size.
- DOS-02 MUST set timeouts: request read, total handler time, database
  `statement_timeout` and `lock_timeout`, outbound calls (EXT-02), job
  execution.
- DOS-03 Every user-driven query MUST be paginated with a maximum page
  size. Large sets SHOULD use cursor pagination. No unbounded queries.
- DOS-04 Every user-selectable filter and sort MUST be backed by an index.
  No leading-wildcard `LIKE` on large tables. Sort fields come from an
  allow-list (INJ-02).

### 16.2 Expensive operations and fairness

- DOS-05 Rate limits MUST be layered (trusted client IP, user, account,
  endpoint class), kept in a shared store, answered with `429` plus
  `Retry-After`, and configurable without a deploy.
- DOS-06 Expensive operations (password hashing, search, reports, exports,
  imports, PDF and image processing, message sends, vendor calls) MUST
  require authentication where possible, MUST have their own stricter
  limits, MUST run asynchronously through a queue when long, and MUST have
  per-user concurrency limits.
- DOS-07 Cheap checks run first: validate, authenticate and rate-limit
  before hashing, querying or calling vendors.
- DOS-08 Per-user (or per-account) quotas MUST cover CPU-heavy jobs,
  storage, messages and API calls, so one user cannot starve the others.

### 16.3 Parser and content bombs

- DOS-09 Decompression MUST cap output size and compression ratio
  (archives and compressed request bodies). Image decoding MUST check
  pixel dimensions before decoding (pixel floods). See also PARSE-01,
  PARSE-04, PARSE-06 and FILE-09.

### 16.4 Queues, retries and caches

- DOS-10 Queues MUST be bounded, with backpressure. Jobs MUST have
  timeouts and a maximum attempt count; failures go to a dead-letter
  queue.
- DOS-11 Retries MUST use exponential backoff with jitter and a retry
  budget. MUST NOT retry 4xx responses, except 408 and 429 with backoff.
  Circuit breakers SHOULD protect every vendor.
- DOS-12 Our own clients (web app, SDKs, mobile apps) MUST back off on
  `429` and `503`.
- DOS-13 Caches SHOULD coalesce concurrent misses (single-flight) and
  jitter TTLs, and MAY serve stale data on error.
- DOS-14 Repeated identical errors SHOULD be aggregated rather than logged
  one by one; log volume per request SHOULD be bounded.

### 16.5 Long-lived connections

- DOS-15 WebSocket and server-sent-event connections MUST have per-user
  connection limits, message size and rate limits, heartbeats, idle
  timeouts, and re-authentication when the token expires.

### 16.6 Scaling and health checks

- DOS-16 Application servers MUST be stateless (sessions in a shared
  store), so they scale horizontally.
- DOS-17 Liveness checks MUST NOT touch external dependencies. Readiness
  checks MUST use short timeouts.
- DOS-18 Account lockout MUST NOT be usable for denial of service
  (AUTHN-07).

## 17. Secrets, configuration, build and CI (SEC, CFG, CI)

### 17.1 Secrets

- SEC-01 Secrets MUST be loaded at runtime from a secret manager, or
  injected by the platform. They MUST NOT appear in the repo, container
  images, client bundles, logs, error messages, test fixtures, CI output
  or build arguments.
- SEC-02 CI MUST authenticate to cloud services through OIDC federation,
  and the app SHOULD use workload identity. No static cloud keys.
- SEC-03 The app MUST support key rotation without downtime: accept the
  current and the previous signing or decryption key during a rotation
  window, and reload secrets without a restart.
- SEC-04 Each environment MUST have its own secrets. Nothing is shared
  between staging and production.
- SEC-05 Anything sent to the browser is public. Only publishable keys may
  ship to clients.

### 17.2 Configuration and container image

- CFG-01 Configuration MUST be typed and validated at startup. Defaults
  MUST be the secure option, so a missing setting is the safe one.
- CFG-02 In production mode the app MUST refuse to start if: debug is on;
  a secret is empty or a known default; CORS is permissive; TLS settings
  are missing; sandbox or test vendor credentials are configured; or a
  required security setting is absent.
- CFG-03 Production builds MUST NOT contain default accounts, sample apps,
  seed users or test routes. The first admin MUST be created with a
  one-time setup token.
- CFG-04 Container images MUST use a minimal base image pinned by digest;
  a multi-stage build without compilers or package managers in the runtime
  stage; a non-root user; compatibility with a read-only root filesystem;
  no secrets in layers or build arguments; a `.dockerignore` that excludes
  `.git`, `.env` and local artifacts.
- CFG-05 Local development MUST use fake vendors and synthetic data.
  Production data and credentials MUST NOT be used on developer machines.
- CFG-06 Development, test and production MUST share one configuration
  schema, with different values and credentials.

### 17.3 CI and build files

- CI-01 Third-party CI actions and plugins MUST be pinned to a commit SHA.
  Pipeline tokens MUST default to read-only. Jobs that run untrusted (fork)
  code MUST NOT have access to secrets.
- CI-02 Pipelines SHOULD build once and promote the same artifact through
  every environment, sign it, and produce an SBOM.
- CI-03 Lockfiles MUST be committed and used (`npm ci`,
  `pip install --require-hashes`, or the ecosystem equivalent). Installs
  MUST use the project's registry proxy, if there is one. Install scripts
  SHOULD be disabled (`npm ci --ignore-scripts`) unless needed and
  justified.
- CI-04 Internal packages MUST use a reserved scope or namespace, and the
  proxy MUST NOT fall back to public registries for it (dependency
  confusion).
- CI-05 The pipeline MUST scan dependencies for known vulnerabilities.
  Dependencies that are no longer used MUST be removed.
- CI-06 Database migrations MUST be deployable separately from the code
  that depends on them, so each can be rolled back.


## 18. Logging, audit trail and kill switches (LOG)

### 18.1 Logs

- LOG-01 Logs MUST be structured and MUST include the actor ID, request ID
  and trace ID. Tracing SHOULD span services, queues and vendor calls.
- LOG-02 MUST log every security decision, successes and failures alike:
  sign-ins, MFA events, access-control denials, server-side validation
  failures, webhook signature failures, rate-limit rejections.
- LOG-03 MUST NOT log passwords, OTPs, tokens, session cookies,
  `Authorization` headers, API keys, or full card, account or ID numbers.
  Redaction MUST happen in the logging layer, using an allow-list of
  fields.
- LOG-04 Personal data in logs MUST be minimized.
- LOG-05 Security-relevant logging MUST NOT depend on debug flags.
  Timestamps MUST be UTC with an explicit offset.

### 18.2 Audit trail

- LOG-06 The audit trail MUST be separate from debug logs, append-only and
  tamper-evident (write-once storage or a hash chain).
- LOG-07 Audit records MUST capture who, what, when (UTC), from where,
  and before/after values for: sign-ins; MFA and recovery changes; role
  and permission changes; access denials on sensitive resources; exports;
  impersonation; configuration changes; API key lifecycle; money
  movements.
- LOG-08 The audit trail MUST make it possible to tell which users and
  which data an actor touched in a given time window.

### 18.3 Security events

- LOG-09 The app MUST emit named `SecurityEvent`s, so operations can alert
  without reading code, for at least: failed logins; OTP sends and
  failures; password resets; spikes of object-ID 404s per actor
  (enumeration); SMS verify rate per country; SMS budget exhausted;
  webhook signature failures; new platform admin; role grants (admin
  above all); impersonation start; mass export; rate-limit and quota
  rejections; error rate; queue depth; dead-letter growth; vendor latency
  beyond its timeout budget.

### 18.4 Kill switches

- LOG-10 Kill switches MUST exist and be covered by tests: revoke sessions
  per user and globally; invalidate all API keys of a user; disable an
  integration or feature flag; put an account into read-only mode.
- LOG-11 Secrets MUST be hot-reloadable (SEC-03), so a leaked key can be
  rotated without a deploy.


## 19. Personal data (PRIV)

- PRIV-01 Schema columns MUST be classified (`personal`, `sensitive`,
  `secret`). The classification drives log redaction, export, deletion
  and encryption.
- PRIV-02 Features MUST collect only the data they need.
- PRIV-03 Retention and deletion MUST be implemented as jobs that also
  cover caches, search indices, file storage, vendors and analytics.
- PRIV-04 Account deletion MUST remove or anonymize the user's personal
  data in every store (PRIV-03), or crypto-shred it (CRY-04).
- PRIV-05 Users MUST be able to export and erase their own data
  (data-subject requests).
- PRIV-06 Non-production environments MUST use synthetic or anonymized
  data.
- PRIV-07 Personal data MUST NOT be sent to third-party analytics.
  Non-essential trackers MUST NOT load before consent where consent is
  required.


## 20. Design review and testing (TEST)

- TEST-01 Threat model per feature. For every feature touching identity,
  money, permissions, personal data, files or third parties, answer in the
  design note or PR description:
  1. Which assets and whose data does it touch?
  2. Who may call it, and what stops everyone else (authentication,
     authorization)?
  3. Which inputs cross a trust boundary, and how is each validated?
  4. What happens if it runs twice, concurrently, out of order, or 10,000
     times a minute?
  5. What does one call cost (CPU, database, money), and what limits it?
  6. What does it log, and how would anyone notice abuse?
  7. Which rules in this file apply, and does it deviate from any?
- TEST-02 Every bug fix MUST start with a failing test that reproduces the
  bug.
- TEST-03 Write these tests together with the code they cover:
  - user isolation: for every endpoint, export, search, job and channel,
    user A gets their own object, a 404 for user B's object, only the
    granted permission on an object B shared, and a 404 again once the
    share is revoked;
  - authorization matrix: each role x action x ownership cell allows or
    denies as specified (AUTHZ-16);
  - domain rules: invariants, state transitions, money and time
    arithmetic, with property-based tests where inputs vary widely;
  - database: constraints, row-level security if used, and migrations
    from empty and from N-1 to N, against a real database;
  - concurrency: parallel requests on a unique or idempotent operation
    produce exactly one effect;
  - webhooks and vendors: bad signature, stale timestamp, replayed event,
    vendor timeout, malformed response;
  - sign-up abuse: repeated sign-ups for one address, after the pending
    sign-up expires and with `+tag` or dot variants, send no more messages
    than MSG-16 allows, and a suppressed address gets none;
  - security regressions: CSRF token and `Origin` checks, SSRF block
    list, headers, cookie flags, upload type checks, fail-to-start
    configuration, kill switches, rate limits and quotas;
  - parsers and file handlers: malformed and hostile input (fuzz where a
    fuzzing harness exists).
- TEST-04 Security tests MUST NOT be skipped, marked flaky or deleted
  without a replacement and a reason in the commit message.


## 21. OWASP Top 10:2025 coverage

| Category | Covered by |
| --- | --- |
| A01 Broken Access Control (includes SSRF and CSRF) | ISO, AUTHZ, DATA, WEB-05..12, EXT-17..23 |
| A02 Security Misconfiguration (includes XXE) | CFG, WEB-01..06, HTTP-04, PARSE-01 |
| A03 Software Supply Chain Failures | AI-01, CI |
| A04 Cryptographic Failures | CRY, SEC, AUTHN-03 |
| A05 Injection (includes XSS) | INJ, WEB-13..16, PARSE |
| A06 Insecure Design | PRIN, BIZ, TEST-01, DOS |
| A07 Authentication Failures | AUTHN |
| A08 Software or Data Integrity Failures | CI-02, CI-03, PARSE-03, EXT-12..16 |
| A09 Security Logging and Alerting Failures | LOG |
| A10 Mishandling of Exceptional Conditions | BIZ-13..17, DOS-10..14 |


## 22. Before committing

- [ ] Threat-model questions answered where required (TEST-01)
- [ ] Every new route, resolver, RPC method, job and socket handler has a
      policy and authorization-matrix rows (AUTHZ-05, AUTHZ-16)
- [ ] Data access only through `DataAccess`; IDOR test added (DATA-01,
      TEST-03)
- [ ] New stores, keys, channels and files are namespaced by owner, and
      every referenced object is authorized (ISO-10, ISO-15)
- [ ] Requests schema-validated; writable fields allow-listed; response
      DTOs used (API-01, AUTHZ-08, AUTHZ-09)
- [ ] New state-changing endpoints CSRF-protected; no GET side effects
      (WEB-07, WEB-08)
- [ ] New endpoints have size, rate, page-size and time limits; expensive
      work async with per-user quotas (DOS-01..08)
- [ ] User-controlled URLs go through `EgressClient`; egress list updated
      (EXT-17, EXT-25)
- [ ] Output encoded for its context; no unsafe DOM sinks (INJ-07..09,
      WEB-13)
- [ ] New invariants backed by constraints; state changes through
      transition functions (BIZ-02, BIZ-07)
- [ ] Retryable mutating endpoints accept an idempotency key (BIZ-09)
- [ ] External calls have timeouts and bounded retries, and run outside
      database transactions (EXT-02, EXT-03, EXT-05)
- [ ] Errors fail closed; nothing swallowed; resources released on error
      paths (BIZ-13, BIZ-16)
- [ ] No secrets, tokens, OTPs or personal data in code, logs, errors or
      fixtures (SEC-01, LOG-03)
- [ ] Security-relevant actions write audit records and emit security
      events (LOG-07, LOG-09)
- [ ] New dependency justified and verified; lockfile updated (AI-01,
      CI-03)
- [ ] Tests written from the specification, including misuse cases; bug
      fixes start with a failing test (AI-05, BIZ-18, TEST-02)
- [ ] Migrations backward compatible (DATA-14)


## 23. References

- OWASP Top 10:2025: https://top10.owasp.org/2025/
- NIST SP 800-63B-4 (Digital Identity Guidelines, Authentication):
  https://pages.nist.gov/800-63-4/sp800-63b.html
- Twilio, preventing SMS pumping fraud:
  https://www.twilio.com/docs/messaging/guides/preventing-messaging-fraud
- Cloud Security Alliance, slopsquatting research note (April 2026):
  https://labs.cloudsecurityalliance.org/research/csa-research-note-slopsquatting-ai-supply-chain-20260419/
