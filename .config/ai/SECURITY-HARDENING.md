# Security Hardening Rules for Development

Security rules for writing a multi-user, multi-role, multi-database web
application with transactional email, SMS one-time codes, 2FA,
third-party integrations and complex business logic. Most rules apply to
any web application or service; rules for features a project does not
have are conditional (section 0.2), so that a small project does not
build machinery it does not need.


## 0. How to use this file

### 0.1 Scope

These rules cover writing and testing code, including the CI, container
and infrastructure files in the repository. Operating the application
(hosting, DNS, provider accounts, monitoring, backups, incident response)
is out of scope. Workflow rules (commits, tests, when to ask) are in
AGENTS.md.

### 0.2 Requirement levels

| Level | Meaning |
| --- | --- |
| MUST | Universal security invariant. A violation blocks the merge. |
| SHOULD | Strong default. A deviation needs a reason in the commit message: `Deviation: <rule ID>: <reason>`. |
| CONDITIONAL | Mandatory only where the technology, feature or exposure named in its tag exists. There it binds as written; elsewhere it does not apply, and nothing has to be built for it. |

MAY marks an option.

A rule is conditional when following it would mean building something
that a project without the feature does not need: an outbox, replica
handling, a read-only gate, SMS fraud controls. A rule that only
constrains code written anyway (how to parse XML, how to validate a JWT)
stays a MUST: it costs nothing where that code does not exist.

Conditional rules carry a tag such as `[if SMS]`:

- The tag names conditions from section 0.5. With `or`, any of them is
  enough; with `and`, all of them must hold.
- A tag on a section or subsection heading applies to every rule under
  it. A rule's own tag replaces the heading's.
- Whether a condition holds is a fact about the code, not a judgment of
  risk. When unsure, treat it as holding.
- A change that introduces a technology or feature (the first background
  job, the first WebSocket endpoint) implements the rules it activates in
  that same change.
- Each project records which conditions hold for it in its own
  repository, for example in its AGENTS.md, and updates that record when
  a change adds or removes one.

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
  payload (ISO-12).
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
  taken from the request context (ISO-08); statement timeouts (DOS-02);
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
- Reads: roles and ownership from the source of truth (STATE-16).
- Never: duplicated as inline role checks elsewhere (AUTHZ-02).

#### Outbound HTTP client: `EgressClient` [if OUTBOUND_HTTP or USER_URLS]

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

#### Message sender: `MessageSender` [if EMAIL or SMS]

- What: functions such as `send_email(template, to, data)` and
  `send_sms(template, to, data)` that hand a message over for sending once
  the current database transaction has committed (BIZ-11): through an
  outbox table and a background worker if the project has one (MSG-13),
  otherwise from an on-commit hook. The provider is called through its
  vendor adapter (EXT-01).
- Does: renders templates with auto-escaping (MSG-03); applies rate
  limits, budgets and the suppression list (MSG-07, MSG-09, MSG-10,
  MSG-16..19); with an outbox, sends with an idempotency key and retries
  (MSG-13).
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

### 0.5 Applicability

The conditions used in tags. The Rules column is generated from the tags
and lists sections, subsections and building blocks by number or name.
The last column is an example of a small project: what a typical
single-database Django application would have.

| Condition | Holds when the project | Rules | Single-database Django app |
| --- | --- | --- | --- |
| `MULTI_PROCESS` | serves requests or runs jobs in more than one process or host; several Gunicorn or uWSGI workers count | STATE-06, STATE-26, STATE-29, DOS-16 | Yes, with more than one worker |
| `MULTI_DB` | keeps source-of-truth data in more than one database or datastore | DATA-06, DATA-07, DATA-09, BIZ-08 | No |
| `REPLICAS` | reads from database replicas, or connects to a primary that can fail over | STATE-17..21 | No |
| `CACHE` | caches data from the database or from vendors beyond one request: a cache framework, Redis, Memcached, HTTP or ORM caching | 4.4, STATE-26, DOS-13 | If the cache framework holds user data |
| `SEARCH` | uses a search engine or index separate from the database | ISO-14 | No |
| `JOBS` | runs background jobs, queues or scheduled tasks | ISO-12, ISO-19, STATE-05, STATE-09, STATE-14, AUTHZ-26, AUTHZ-27, MSG-13, DOS-10 | With Celery, RQ or cron jobs |
| `SERVICES` | consists of several services that call each other | AUTHN-34, AUTHZ-27, BIZ-08 | No |
| `PUBLIC_API` | offers an API to clients other than its own web front end: mobile apps, integrations, customers | STATE-08, STATE-10..12, API-02, API-09, API-10 | If it has an API for apps or integrations |
| `GRAPHQL` | exposes a GraphQL API | API-04 | No |
| `REALTIME` | pushes data to clients over WebSockets, server-sent events or pub/sub | ISO-16, WEB-11, 17.5 | With Django Channels |
| `PASSWORDS` | signs users in with passwords | 5.2, AUTHN-19 | Yes (`django.contrib.auth`) |
| `SSO` | signs users in through an external identity provider | 5.7 | If configured |
| `SIGNUP` | lets anyone create an account | 7.4, MSG-18, MSG-23 | If registration is open |
| `INVITATIONS` | lets users invite other people | AUTHN-29, AUTHN-30 | If used |
| `API_KEYS` | issues API keys or personal access tokens | AUTHN-33, LOG-12 | If used |
| `STAFF_ADMIN` | has an admin or back-office interface for staff | 2.4, AUTHN-35 | Yes, if `django.contrib.admin` is enabled |
| `IMPERSONATION` | lets staff act as a user | AUTHN-36 | No |
| `SHARING` | lets users share objects with other users or through links | ISO-05 | If used |
| `EMAIL` | sends email | `MessageSender`, 7.1, MSG-01, 7.3, MSG-18 | Usually |
| `SMS` | sends SMS or voice messages | `MessageSender`, AUTHN-13, MSG-01, 7.2, 7.3, MSG-23 | If used |
| `OUTBOUND_HTTP` | calls external HTTP APIs | `EgressClient`, 8.1, EXT-25, INJ-27, LOG-13 | If it integrates vendors |
| `USER_URLS` | fetches URLs that users supply, or sends webhooks to them | `EgressClient`, 8.3 | Rarely |
| `WEBHOOKS_IN` | receives webhooks | 8.2, LOG-13 | If it integrates vendors |
| `PAYMENTS` | handles payments, refunds, payouts or other money movements | STATE-08, STATE-10..12, AUTHZ-11, EXT-11, BIZ-09 | If used |
| `UPLOADS` | accepts files from users | ISO-17, section 14, FILE-08 | If a `FileField` takes uploads |
| `DOCGEN` | generates or converts documents or images: PDF, LaTeX, office files, thumbnails | EXT-22, INJ-14, FILE-08 | If used |
| `RICH_TEXT` | accepts HTML or Markdown from users | INJ-17, INJ-22 | If used |
| `IMPORT_EXPORT` | imports or exports files of records, such as CSV or spreadsheets | 9.5, INJ-25 | If used |
| `USER_CODE` | evaluates formulas, scripts or rules that users supply | INJ-15 | No |
| `READ_ONLY_MODE` | offers a read-only mode for the application or for single accounts | 4.6 | No |
| `LLM` | calls a large language model at runtime | AI-06 | No |
| `CONTAINERS` | builds container images in this repository | CFG-04 | If it has a Dockerfile |
| `CI` | keeps CI pipeline configuration in this repository | SEC-02, 18.3 | Usually |

### 0.6 Framework controls

A rule is met by the framework's own control where there is one: enable
it, configure it strictly and do not bypass it. Do not build a second one
(PRIN-08). A framework mechanism that gives the same guarantee counts,
even if it works differently from the one a rule describes, and many
frameworks already provide the building blocks of section 0.4. In a
Django application, for example:

| Rule | Django control |
| --- | --- |
| Request context (0.4) | `request.user` and the session |
| Data-access layer (DATA-01) | model managers and querysets, with any raw SQL kept inside them |
| Configuration loader (CFG-01, CFG-02) | the settings module, checked with `manage.py check --deploy` in CI |
| Parameterized queries (INJ-01) | the ORM, and `params` for `raw()` and `cursor.execute()` |
| Output encoding (INJ-16) | template auto-escaping, without `mark_safe` or the `safe` filter on user data |
| CSRF (WEB-07) | `CsrfViewMiddleware`, without `csrf_exempt` on cookie-authenticated views |
| Clickjacking (WEB-01) | `XFrameOptionsMiddleware`, next to `frame-ancestors` |
| HSTS, MIME sniffing, referrer, cookies (WEB-02..04) | `SECURE_HSTS_SECONDS`, `SECURE_CONTENT_TYPE_NOSNIFF`, `SECURE_REFERRER_POLICY`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` |
| Host header (HTTP-01) | `ALLOWED_HOSTS` |
| Password hashing (AUTHN-03) | `Argon2PasswordHasher` first in `PASSWORD_HASHERS` |
| Signing-key rotation (SEC-03) | `SECRET_KEY_FALLBACKS` |


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
- PRIN-11 Whatever a user can check and then act on, they can race. Every
  request may arrive twice, out of order, or in parallel with itself
  (STATE).

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

- ISO-01 Every record of user data MUST have an explicit owner: a
  `NOT NULL` owner column, or a mandatory reference to an owned parent.
  Data without an owner is platform data, which users can at most read.
- ISO-02 Access to another user's data MUST come from an explicit grant
  (a share, a membership, a role over that object), checked by
  `authorize()`. Knowing an ID, a URL or a file name is never a grant.
- ISO-03 Write paths MUST authorize every object they reference, not only
  the one in the URL: attaching a file to a document, adding an item to an
  order, moving a record into a folder or setting a parent ID each need a
  check on the referenced object.
- ISO-04 Where data is strictly per user, foreign keys SHOULD include the
  owner, for example
  `FOREIGN KEY (owner_id, folder_id) REFERENCES folders (owner_id, id)`,
  so that the database rejects links across users.
- ISO-05 [if SHARING] Share links are grants: at least 128 random bits,
  stored hashed, bound to one object and one permission, expiring, revocable
  and logged on use. A share link MUST NOT grant more than its creator holds
  (AUTHZ-10).
- ISO-06 Revoking a grant MUST take effect on the next request, including
  for open WebSocket subscriptions, cached results and signed URLs (keep
  their lifetime short).
- ISO-07 New data and new features are private by default. Anything
  visible to other users (public profiles, shared spaces) MUST be marked
  as such explicitly in the data model, never inferred.
- ISO-08 Data-access functions for restricted data MUST take the
  `RequestContext` and apply ownership or permission filters in the query
  itself (AUTHZ-06, AUTHZ-07).
- ISO-09 MUST return 404, not 403, for objects the actor may not see, so
  their existence is not revealed.
- ISO-10 Public identifiers SHOULD be non-sequential (UUIDv7, ULID). They
  are never an access control.

### 2.2 Stores, channels, jobs and outputs

- ISO-11 Derived stores MUST NOT bypass authorization. Search results,
  cached objects and reports are filtered by the same permission rules as
  the source; cache keys for permission-dependent content MUST include the
  actor or its permission scope.
- ISO-12 [if JOBS] Background jobs MUST carry the actor in the payload,
  re-create the `RequestContext` and re-check authorization when they run.
- ISO-13 Every key derived from user data MUST be namespaced by its owner:
  cache keys, object-storage paths, search documents, queue messages,
  pub/sub channel names, rate-limit buckets, lock names, temporary file
  names and idempotency keys. A namespace prevents mix-ups; it is not a
  permission, and the code reading the data still checks access.
- ISO-14 [if SEARCH] Search engines MUST apply the actor's access filter
  inside the query (security trimming), so that hits, counts, facets,
  highlights and suggestions never come from data the actor may not see.
- ISO-15 Aggregates shown to users (counts, sums, rankings, "people who
  viewed this") MUST be computed only over data the actor may see;
  otherwise they reveal the existence and the values of other users'
  data.
- ISO-16 [if REALTIME] Real-time channels (WebSocket, server-sent events,
  pub/sub) MUST authorize every subscription on the server and filter every
  message per recipient. An unguessable channel name is not access control.
- ISO-17 [if UPLOADS] User files MUST be stored privately (no public buckets
  or directories) and served only through short-lived signed URLs bound to
  one object (FILE-10). Temporary files MUST get random names in a private
  directory, be readable only by the process, and be deleted after use.
- ISO-18 Exports, reports and generated documents MUST be produced with
  the requesting user's permissions at generation time, and MUST be
  downloadable only by that user.
- ISO-19 [if JOBS] Batch jobs that process many users MUST handle each
  user's data in that user's context (or in a declared system context), and
  MUST NOT mix several users' data into one output, message or file unless
  the feature is explicitly about that.
- ISO-20 Error messages, validation messages and notifications MUST NOT
  disclose another user's data: names, emails, the value behind a
  unique-constraint violation, other rows in a stack trace.

### 2.3 Requests and processes

- ISO-21 MUST NOT leak per-request state through pooled connections: no
  session-level settings or temporary tables that outlive the transaction;
  reset connection state on checkout.
- ISO-22 Request state (actor, roles, request data) MUST live in the
  request context. It MUST NOT be kept in module-level or global
  variables, class or static fields, singletons, or thread-locals that
  outlive the request: worker threads and event loops serve many users.
- ISO-23 In asynchronous code, the request context MUST travel through the
  runtime's context mechanism (for example Python `contextvars`, Node.js
  `AsyncLocalStorage`) into every task and callback the request starts,
  and MUST be cleared when the request ends. Code running outside a
  request (timers, pool callbacks) MUST NOT see a previous request's
  context.
- ISO-24 Memoization and per-process caches whose result depends on the
  actor (`lru_cache`, memoize decorators, ORM identity maps and sessions,
  GraphQL DataLoaders) MUST be created per request, or keyed by actor
  (ISO-11).
- ISO-25 Buffers and objects reused across requests (object pools,
  `sync.Pool`, reused byte arrays) MUST be cleared before reuse.
  Uninitialized allocations (for example Node.js `Buffer.allocUnsafe`)
  MUST NOT be returned to users or written to storage.

### 2.4 Platform staff [if STAFF_ADMIN]

- ISO-26 Platform-staff access to user data MUST go through a separate,
  audited code path with explicit break-glass approval.


## 3. Data access and multiple databases (DATA)

### 3.1 Data access

- DATA-01 Each database MUST have exactly one data-access layer
  (`DataAccess`). Feature code MUST NOT open connections, use the database
  driver or ORM session, or build queries outside it. An architecture test
  MUST enforce this.
- DATA-02 Each database MUST be accessed with its own least-privilege
  credentials. The application user MUST NOT run DDL; migrations MUST use
  a separate user; read-only workloads SHOULD use a read-only user. A
  service MUST NOT hold credentials for databases it does not use.
- DATA-03 Database connections MUST use TLS with certificate verification
  where the database supports it, and MUST set statement timeouts
  (DOS-02).
- DATA-04 PostgreSQL row-level security MAY add a second layer for
  user-owned data. If used, the application role MUST NOT own the tables
  or have `BYPASSRLS`, and the actor MUST be set with `SET LOCAL` inside
  the transaction.

### 3.2 Several databases, one consistent state

- DATA-05 Each kind of data MUST have exactly one source of truth. Copies
  in other stores (caches, search indices, read replicas, reporting
  databases) are derived and MUST be rebuildable from it.
- DATA-06 [if MULTI_DB] MUST NOT use distributed transactions across
  databases. Use the transactional outbox and idempotent consumers
  (STATE-09, BIZ-11).
- DATA-07 [if MULTI_DB] References between databases cannot use foreign
  keys. The code MUST validate them on write, and reconciliation jobs MUST
  detect orphans and drift (BIZ-09).
- DATA-08 Migrations MUST be backward compatible (expand, migrate,
  contract), so the app runs against schema N and N-1. Each database
  tracks its own schema version; the migrator MUST be idempotent and MUST
  report drift as an error.
- DATA-09 [if MULTI_DB] Identifiers that travel between databases SHOULD be
  globally unique (UUIDs), so records from different stores cannot be
  confused.
- DATA-10 Deleting data MUST reach every store that holds a copy
  (PRIV-03).


## 4. Concurrency, replicas, caches and in-memory state (STATE)

### 4.1 Parallel execution

- STATE-01 Check-then-act sequences MUST be atomic: a guarded update,
  `SELECT ... FOR UPDATE`, an optimistic version column, or a unique
  constraint. Counters MUST use atomic increments.
- STATE-02 Limits that protect security MUST be enforced atomically: OTP
  and login attempt counters, rate limits, quotas, coupon and voucher
  redemption, invitation use, balances. Attackers send many requests at
  once to get past a read-check-write sequence (limit overrun); use an
  atomic increment-and-compare in the database or shared store, or a
  unique constraint.
- STATE-03 Single-use tokens (password reset, invitation, one-time code,
  one-time share link) MUST be consumed by one conditional update, and the
  action runs only if exactly one row changed:

  ```sql
  UPDATE tokens SET used_at = now()
   WHERE token_hash = :h AND used_at IS NULL AND expires_at > now();
  ```

- STATE-04 Read-modify-write of permission, balance or status fields MUST
  use a row lock or an optimistic version check; never last-write-wins
  (lost updates).
- STATE-05 [if JOBS] Jobs processed by parallel workers MUST be claimed
  atomically (`SELECT ... FOR UPDATE SKIP LOCKED`, or a lease with an
  expiry). A worker whose lease has expired MUST NOT commit its result;
  check a fencing token or version on commit.
- STATE-06 [if MULTI_PROCESS] Distributed locks (Redis and similar) are
  advisory and can expire in the middle of an operation. Security-relevant
  correctness MUST NOT depend on them alone; back them with a database
  constraint or a fencing token.
- STATE-07 Parallel work inside one request (threads, tasks, promises)
  MUST receive the request context explicitly (ISO-23) and MUST NOT share
  mutable state without synchronization.

### 4.2 Idempotency

- STATE-08 [if PUBLIC_API or PAYMENTS] Mutating endpoints that clients may
  retry MUST accept an `Idempotency-Key`, store key, request hash and
  response, replay the stored response, and reject reuse of a key with a
  different request.
- STATE-09 [if JOBS] Queue consumers MUST be idempotent; delivery is
  at-least-once.
- STATE-10 [if PUBLIC_API or PAYMENTS] Idempotency keys MUST be scoped to
  the actor and the operation, looked up as `(actor, operation, key)`. A key
  sent by another user MUST NOT return the first user's stored response
  (ISO-13).
- STATE-11 [if PUBLIC_API or PAYMENTS] Two concurrent requests with the same
  key MUST NOT both run: reserve the key first under a unique constraint
  (status "in progress"); the second request waits or gets `409`.
- STATE-12 [if PUBLIC_API or PAYMENTS] Stored responses MUST expire (for
  example after 24 hours) and are personal data: they get the same
  protection and deletion as the data they contain.
- STATE-13 Effects MUST be idempotent in the data, not only in the API
  layer: unique constraints on natural keys (external payment ID, vendor
  event ID, message ID) make it impossible for a retry to create a second
  record.
- STATE-14 [if JOBS] A queue consumer MUST record the message ID in the same
  transaction as the message's effect, so that a crash between effect and
  acknowledgment cannot apply it twice.
- STATE-15 Operations that are not idempotent MUST NOT be retried
  automatically (by clients, proxies, job runners or SDK retry settings)
  unless they carry an idempotency key (EXT-03).

### 4.3 Primary and replicas

- STATE-16 Security decisions (session validity and revocation, roles and
  permissions, one-time-code use, balances) MUST read the source of truth,
  never a lagging replica or a long-lived cache.
- STATE-17 [if REPLICAS] Writes MUST go to the primary only. Replica
  connections MUST use read-only database users, so that a bug cannot write
  to a replica or make it diverge.
- STATE-18 [if REPLICAS] Read your own writes in security flows: after a
  password or MFA change, a role or grant change, a logout, a session
  revocation or a token consumption, every following check MUST see the
  change. Read from the primary, or wait until the replica has replayed the
  change.
- STATE-19 [if REPLICAS] Security-critical writes (revocations, password and
  MFA changes, role removals, token consumption) SHOULD be committed with
  synchronous replication where the database offers it (for example
  PostgreSQL `SET LOCAL synchronous_commit = remote_apply` with a
  synchronous standby), so that a failover cannot lose them and silently
  restore revoked access.
- STATE-20 [if REPLICAS] After a failover the application MUST write only to
  the new primary: connect with a read-write target (for example libpq
  `target_session_attrs=read-write`), and do not cache the primary's
  address beyond the driver's own reconnect logic.
- STATE-21 [if REPLICAS] Replicas and reporting copies hold the same
  personal data and secrets as the primary. Code that reads them gets the
  same access control, and no broader credentials, than code that reads the
  primary.

### 4.4 Caches [if CACHE]

- STATE-22 A cache key MUST include every input that changes the cached
  value: the actor or its permission scope (ISO-11), locale, format, API
  version, feature flags. Build keys from a structured, escaped encoding
  or a hash of a canonical serialization, never by joining user strings
  with a separator (key collisions).
- STATE-23 Values read from a cache are untrusted. Store them as data
  (JSON or another plain format), never as native serialized objects
  (`pickle`, Java serialization): whoever can write to the cache could
  otherwise run code (PARSE-03).
- STATE-24 MUST NOT cache secrets, tokens, one-time codes or password
  hashes. Personal data MAY be cached with a short TTL, in a cache that
  requires authentication and TLS.
- STATE-25 Security changes MUST invalidate what they affect: logout,
  password change, role or grant change, account deletion and data
  deletion remove the related entries, or the TTL is short enough to be
  the accepted delay (AUTHZ-14). Cached authorization decisions and other
  cached "allowed" results are the critical case.
- STATE-26 [if CACHE and MULTI_PROCESS] With several application instances,
  each has its own in-process cache. A revocation MUST reach all of them
  (broadcast invalidation or a short TTL); whatever must take effect
  immediately (sessions, permissions, kill switches) MUST NOT rely on an
  in-process cache alone.
- STATE-27 ORM second-level caches, query caches and HTTP response caches
  MUST be keyed by actor, or used only for data that every user may see.
- STATE-28 Each service uses its own cache namespace and credentials. The
  application's cache user MUST NOT be able to run administrative commands
  (for Redis, an ACL without `FLUSHALL`, `CONFIG`, `KEYS` or `DEBUG`, and
  `EVAL` only if needed).

### 4.5 In-memory state

- STATE-29 [if MULTI_PROCESS] Rate limiters, attempt counters, locks,
  sessions and revocation lists MUST live in a store shared by all instances
  (the database or a shared cache). Per-process memory exists once per
  instance and resets on restart, so it enforces no limit: an attacker
  spreads requests over instances or waits for the next deploy.
- STATE-30 Large inputs and outputs (uploads, imports, exports, query
  results) MUST be processed as streams with bounded buffers, never loaded
  into memory whole (DOS-01).
- STATE-31 Anything that must not be lost (audit records, revocations,
  outbox messages) MUST be persisted before the operation is reported as
  done. In-memory queues and buffers lose their contents on a crash or
  restart.
- STATE-32 Secrets and personal data in memory: keep them only as long as
  needed, and never put them into exception messages, debug output,
  global registries, or objects that get logged or serialized. Where the
  library allows it, leave keys in the KMS and send it the data, instead
  of loading the key into the process.
- STATE-33 Heap dumps, core dumps and profiles contain secrets and
  personal data. Production builds MUST NOT expose heap-dump or profiling
  endpoints without authentication (HTTP-04), and code MUST NOT write
  dumps or profiles to shared or world-readable locations.

### 4.6 Read-only mode [if READ_ONLY_MODE]

- STATE-34 Read-only mode, for the whole application (maintenance,
  incident response) or for one account (suspended or frozen), MUST be
  enforced on the server by one central gate. Every handler declares in
  its policy whether it reads or writes (AUTHZ-05); undeclared handlers
  count as writing, and writing handlers are denied while the mode
  applies.
- STATE-35 Reading handlers MUST NOT have side effects (WEB-08); otherwise
  read-only mode keeps writing.
- STATE-36 The gate MUST also stop background jobs, schedulers, queue
  consumers and the outbox worker from changing data or sending messages.
  Inbound webhooks get a retryable status (for example `503`), so that the
  sender delivers them later.
- STATE-37 Application-wide read-only mode SHOULD also hold in the
  database: switch to a read-only database user or read-only
  transactions, so that a handler the gate missed fails instead of
  writing.
- STATE-38 Security state keeps working in read-only mode: sign-in
  throttling, attempt counters, session revocation, logout and audit
  records MUST still be written to a store that stays writable, or the
  operation they protect MUST be refused. A check MUST NOT be skipped
  because its write would fail.
- STATE-39 Read-only mode MUST NOT relax authentication or authorization:
  no anonymous or cached access "during maintenance".
- STATE-40 Read-only mode for one account applies to everything acting for
  it: sessions, API keys, scheduled jobs and integrations.
- STATE-41 The mode is read from the shared store, so that every instance
  applies it at once. Switching it is a privileged, audited action
  (LOG-07).


## 5. Identity and authentication (AUTHN)

### 5.1 General

- AUTHN-01 MUST use a maintained authentication library or identity
  provider. MUST NOT implement password hashing, OTP generation, session
  handling or token cryptography by hand.
- AUTHN-02 MUST NOT ship default, sample or hard-coded credentials for any
  role or environment.

### 5.2 Passwords [if PASSWORDS]

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

### 5.3 Brute force and enumeration

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

### 5.4 Second factors and one-time codes

- AUTHN-11 MUST support passkeys (WebAuthn) and SHOULD make them the
  default second factor. MUST allow several passkeys per user.
- AUTHN-12 TOTP: secrets MUST be encrypted at rest (CRY-04); accept at
  most one time step of clock skew; MUST reject reuse of a code within its
  validity window.
- AUTHN-13 [if SMS] SMS and voice codes are a fallback only. NIST SP
  800-63B-4 classifies PSTN delivery as a restricted authenticator. The app
  MUST offer a phishing-resistant option.
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

### 5.5 Recovery and sensitive changes

- AUTHN-19 [if PASSWORDS] Password-reset tokens MUST have at least 128 bits
  of entropy, be stored hashed, be single use, expire within 15 to 60
  minutes, and be invalidated by any password change.
- AUTHN-20 Links sent by email or SMS MUST be built from configured base
  URLs, never from `Host` or `X-Forwarded-Host`.
- AUTHN-21 A password reset MUST NOT bypass MFA. Resetting MFA MUST
  require stronger proof, apply a cooling-off delay, and notify every
  existing channel.
- AUTHN-22 MUST require step-up re-authentication before changing email,
  phone, password, MFA, payout details or API keys, and before granting
  admin roles. MUST notify the previous address or number with a way to
  report or undo the change.

### 5.6 Sessions and tokens

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

### 5.7 SSO and federation [if SSO]

- AUTHN-27 OIDC and OAuth: MUST use `state` and `nonce`, PKCE and
  exact-match redirect URIs, and MUST validate signature, issuer and
  audience. SAML: MUST validate the assertion signature, audience,
  recipient and validity window, and MUST parse with DTDs disabled
  (PARSE-01).
- AUTHN-28 MUST NOT link or create accounts by email from an external
  identity provider unless the email is verified and that provider is
  configured as authoritative for the email's domain.

### 5.8 Invitations and account lifecycle

- AUTHN-29 [if INVITATIONS] Invitation tokens MUST be random, stored hashed,
  single use, expiring, and bound to the invited email. The role MUST come
  from the stored invitation, never from the accept request.
- AUTHN-30 [if INVITATIONS] Accepting an invitation while signed in with a
  different email MUST require explicit confirmation.
- AUTHN-31 Deactivating or deleting an account MUST immediately revoke its
  sessions, API keys and scheduled jobs. Removing a role MUST take effect
  on the next request (STATE-16).
- AUTHN-32 Uniqueness of emails and usernames MUST be checked on a
  normalized form (Unicode NFKC plus case folding). Mail MUST be sent to
  the address as entered. Usernames shown to others SHOULD reject
  mixed-script and confusable characters.

### 5.9 API keys, machine identities and back office

- AUTHN-33 [if API_KEYS] API keys MUST be scoped to one account and an
  explicit permission set, MUST expire, MUST be stored hashed and shown
  once, MUST carry a recognizable prefix (for example `acme_live_`) so
  secret scanners detect leaks, and MUST record last use.
- AUTHN-34 [if SERVICES] Service-to-service calls MUST be authenticated
  (mTLS or signed short-lived tokens) and authorized. Network location is
  never proof of identity.
- AUTHN-35 [if STAFF_ADMIN] The platform back office MUST be a separate
  application or route group with its own authentication, phishing-resistant
  MFA and audit trail, and MUST NOT be reachable with a regular user
  session.
- AUTHN-36 [if IMPERSONATION] Support impersonation ("log in as") MUST be
  explicit, time-boxed, audited and visibly bannered, and MUST NOT allow
  changing credentials, MFA or payout details.
- AUTHN-37 MUST compare secrets (tokens, codes, HMACs, API keys) in
  constant time.


## 6. Authorization, roles and least privilege (AUTHZ)

### 6.1 Policy and enforcement

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
- AUTHZ-11 [if PAYMENTS] Money movements and approvals MUST enforce
  separation of duties: the creator of a payment, refund or price change
  MUST NOT approve it.
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

### 6.2 Roles

- AUTHZ-17 New users MUST get the least-privileged role. Elevated roles
  are granted explicitly by someone allowed to grant them, never by
  default, by sign-up input or by self-service.
- AUTHZ-18 Every role's permissions MUST be listed explicitly. A new
  permission is denied to every role until it is added to the roles that
  need it. No wildcard permissions (`invoice.*`, `*`) outside documented
  platform-staff roles.
- AUTHZ-19 Admin roles get the permissions their job needs, not
  everything. Other users' credentials (password hashes, MFA secrets, API
  keys, tokens) MUST NOT be readable by any role. Reading other users'
  private content (messages, documents) needs a permission of its own and
  is audited (LOG-07).
- AUTHZ-20 Roles that can change roles, credentials, money or other users'
  data MUST require MFA, phishing-resistant where available, and step-up
  for each sensitive action (AUTHN-22).
- AUTHZ-21 Temporary elevation (support, incident work) SHOULD be a grant
  with an expiry that is revoked automatically, not a permanent role
  change.
- AUTHZ-22 Permissions MUST be resolved on each request from the source of
  truth, or from a cache invalidated on change (AUTHZ-14). Tokens MUST NOT
  carry long-lived role claims that outlive a revocation (AUTHN-26).
- AUTHZ-23 These escalation paths MUST be closed: editing one's own roles
  or grants; creating API keys, invitations, share links or OAuth grants
  with more permissions than one holds; resetting the credentials or MFA
  of, or impersonating, a user with more privileges; joining a group or
  role by self-service unless it is explicitly open; gaining a role
  through an unverified email domain.
- AUTHZ-24 No shared accounts: every action is attributable to one actor.
  Service accounts exist per service and purpose, and humans MUST NOT use
  them.
- AUTHZ-25 Confused deputy: code acting on behalf of a user (jobs,
  internal services, vendor callbacks, LLM tools) MUST check that user's
  permissions, not its own. A privileged system identity MUST NOT be used
  to serve a user's request.
- AUTHZ-26 [if JOBS] Jobs that run without a user (system jobs) MUST declare
  the permissions they use and get nothing else. Jobs started by a user run
  with that user's permissions (ISO-12).

### 6.3 Least privilege for code and services

- AUTHZ-27 [if SERVICES or JOBS] Each service, worker and scheduled job MUST
  use its own database user, granted only the tables and operations it
  needs: `SELECT` where it only reads, no `DELETE` where it never deletes,
  no access to other components' tables (DATA-02). The audit table is
  insert-only (LOG-06).
- AUTHZ-28 Read paths SHOULD run on a read-only connection (a read-only
  database user, or `SET TRANSACTION READ ONLY`), so that an injection in
  a read path cannot write.
- AUTHZ-29 Code gets narrow capabilities: pass a component only the
  repository, client or key it needs, not a container of all services, a
  superuser connection or the whole configuration.
- AUTHZ-30 Credentials for third parties and cloud services MUST be scoped
  per integration and per environment, with the narrowest scopes or IAM
  permissions that work (EXT-09, SEC-04).
- AUTHZ-31 Processes run as a non-root user without extra capabilities
  (CFG-04) and write only to the directories they need.


## 7. Transactional email and SMS (MSG)

### 7.1 Email [if EMAIL]

- MSG-01 [if EMAIL or SMS] MUST send all email and SMS through
  `MessageSender`, after the business transaction has committed (BIZ-11).
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

### 7.2 SMS [if SMS]

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

### 7.3 Delivery pipeline [if EMAIL or SMS]

- MSG-13 [if JOBS] The message request MUST be written to an outbox table in
  the same transaction as the business change. A worker sends it with an
  idempotency key per message, retries with exponential backoff and jitter
  on timeouts and 5xx responses, moves it to a dead-letter queue after N
  attempts, and records the provider message ID and delivery status.
- MSG-14 Non-production environments MUST route email and SMS to a sink,
  with an explicit allow-list of test recipients.

### 7.4 Sign-up and verification messages [if SIGNUP]

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
- MSG-18 [if SIGNUP and EMAIL] Every verification email MUST carry a "This
  wasn't me" link that works without signing in. It opens a page whose POST
  button (MSG-05) cancels the pending sign-up and puts the delivery key on a
  sign-up suppression list. The same action MAY be offered through the
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
- MSG-23 [if SIGNUP and SMS] Phone numbers get the same per-destination
  limits and suppression (MSG-16..19). An inbound `STOP` reply, where the
  provider supports it, MUST suppress the number. An unauthenticated visitor
  SHOULD NOT be able to trigger an SMS at all: verify the email address
  first, or put the SMS step behind bot detection (MSG-09).
- MSG-24 Limit hits and attempts on suppressed keys MUST emit
  `SecurityEvent`s.


## 8. Third-party systems (EXT)

### 8.1 Outbound calls [if OUTBOUND_HTTP]

- EXT-01 Each vendor MUST be wrapped in exactly one adapter. Domain code
  MUST NOT use vendor SDK types.
- EXT-02 Every outbound call MUST set connect and read timeouts.
- EXT-03 Retries are allowed only for idempotent operations, with
  exponential backoff, jitter and a cap. Non-idempotent calls MUST carry an
  idempotency key.
- EXT-04 SHOULD isolate vendors with separate worker or connection pools
  (bulkheads) and circuit breakers.
- EXT-05 MUST NOT make network calls inside a database transaction. Make
  them after the commit (BIZ-11).
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
- EXT-11 [if PAYMENTS] Card data MUST NOT touch the application's servers.
  Use the payment provider's hosted fields or redirect, and store only
  provider tokens.

### 8.2 Inbound webhooks [if WEBHOOKS_IN]

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

### 8.3 User-controlled URLs (SSRF) [if USER_URLS]

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
- EXT-22 [if DOCGEN] HTML-to-PDF converters, headless browsers, image
  fetchers and link-preview generators MUST run in an isolated worker, with
  local file access and script execution disabled where possible. Their
  network access MUST follow EXT-18..21.
- EXT-23 MUST NOT return the raw response of a user-supplied URL to the
  user.
- EXT-24 Outbound webhooks sent to user-configured endpoints MUST be
  signed, timestamped, retried with backoff, and logged per delivery.
- EXT-25 [if OUTBOUND_HTTP] The repo MUST contain the list of hosts the app
  legitimately calls (egress allow-list), so operations can enforce it.

## 9. Business logic and data integrity (BIZ)

### 9.1 Invariants and types

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

### 9.2 State machines and multi-step flows

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

- BIZ-08 [if SERVICES or MULTI_DB] Multi-step flows across services or
  databases MUST use sagas with compensating actions.
- BIZ-09 [if PAYMENTS] Data mirrored with vendors (payments, subscriptions)
  MUST have reconciliation jobs that detect and report drift.

### 9.3 Errors

- BIZ-10 Errors MUST fail closed. An exception in authentication,
  authorization, validation or policy evaluation results in deny. No
  catch-all that logs and continues. The whole unit of work MUST roll
  back.
- BIZ-11 Every side effect that must follow a commit (messages, events,
  vendor calls) MUST run only after the commit has succeeded, never inside
  the transaction: from an on-commit hook (for example Django's
  `transaction.on_commit`), or through a transactional outbox when the
  project has a background worker (MSG-13).
- BIZ-12 Clients MUST receive generic error messages with a correlation
  ID; details go to logs only.
- BIZ-13 MUST release every resource (connection, file handle, lock,
  temporary file) on all error paths (`try/finally`, context managers,
  `defer`).
- BIZ-14 MUST check return values and handle missing parameters
  explicitly. No implicit default that grants access or skips a check.

### 9.4 Misuse cases and abuse

- BIZ-15 Every feature MUST list its misuse cases (called twice, out of
  order, concurrently, with negative or huge values, by the wrong role, on
  another user's object, after cancellation, with an old token, at high
  rate) and cover each with a test or a limit.
- BIZ-16 Risky new logic SHOULD ship behind a feature flag usable as a
  kill switch.
- BIZ-17 Business flows open to automation (signup, booking, purchasing,
  coupons, invitations, voting) MUST have per-account limits and
  plausibility checks against bulk abuse and scalping bots.

### 9.5 Imports, exports and bulk operations [if IMPORT_EXPORT]

- BIZ-18 Imports MUST validate every row with the same domain validation
  as the API, enforce file-size, row-count and field-length limits, run
  asynchronously with per-user quotas, and report partial failure
  explicitly (all-or-nothing, or a per-row result file).
- BIZ-19 Exports MUST be authorized per row, run asynchronously when
  large, and be delivered through short-lived signed links, never as email
  attachments.


## 10. AI-generated code (AI)

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
- AI-06 [if LLM] If the product calls an LLM at runtime, the OWASP Top 10
  for LLM Applications applies as well. Model output is untrusted input:
  validate and encode it, never execute it. Text the model reads (user
  input, documents, web pages, emails) can carry instructions (prompt
  injection), so tools and data given to the model MUST be limited to
  what the requesting user may do, and actions with side effects SHOULD
  need the user's confirmation.

## 11. Injection and output encoding (INJ)

Injection happens wherever untrusted data reaches an interpreter as code
instead of data: a database, a shell, a template engine, a browser, a
logger, a document generator. The defense is always the same: send data
through the interpreter's own data channel (bind parameters, argument
arrays, context-aware encoders, structured fields), never by building
code as a string. This holds for data read back from our own stores as
much as for request input.

### 11.1 Queries and data stores

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
- INJ-05 Each datastore has its own parameter API, and code MUST use it:
  - SQL: bind parameters, also inside stored procedures, functions and
    migrations (in PL/pgSQL, `EXECUTE ... USING` for values and
    `format('%I', ...)` for identifiers);
  - MongoDB: query documents built from typed values; never `$where`,
    `$function`, `$accumulator` or `mapReduce` with user input;
  - Redis: arguments passed separately from the command; Lua scripts get
    user data only through `KEYS` and `ARGV`;
  - Elasticsearch and OpenSearch: structured queries (`term`, `match`);
    never `query_string` syntax or scripts built from user input;
  - graph databases (Cypher, Gremlin): query parameters;
  - LDAP: the library's filter and DN escaping.
- INJ-06 Second-order injection: values read from our own database,
  cache, queue, files or logs are still untrusted when they reach an
  interpreter (PRIN-09), and get the same parameters and encoding as
  request input.
- INJ-07 `LIKE` and full-text patterns MUST escape `%`, `_` and the escape
  character in user input; otherwise the user controls the pattern (data
  probing, slow queries).
- INJ-08 Structured formats (JSON, XML, YAML, CSV, URLs, query strings,
  email headers) MUST be produced with a serializer or builder, never by
  concatenating strings that contain user data.

### 11.2 Commands and code

- INJ-09 MUST NOT invoke a shell with untrusted input. Use argument arrays
  without a shell, put `--` before user-supplied arguments, and allow-list
  values where possible.
- INJ-10 MUST NOT evaluate untrusted input as code, template or expression
  (`eval`, `exec`, `Function`, template compilation, EL/OGNL/SpEL,
  server-side template engines).
- INJ-11 Argument injection: a user value passed to a program MUST NOT be
  able to become an option. Put it after `--` and reject values that start
  with `-`. Tools that also follow URLs or protocols (git, curl, ssh,
  rsync, tar, ImageMagick, ffmpeg) MUST be restricted explicitly, for
  example git `protocol.allow`, ffmpeg `-protocol_whitelist`, an
  ImageMagick security policy.
- INJ-12 MUST NOT select code by user input: no dynamic `import`,
  `require` or `include`, no class or function lookup by name
  (`getattr`, reflection, `Class.forName`), no template or file inclusion
  by a user-supplied name. Map allowed values to code through a fixed
  table.
- INJ-13 User input MUST NOT be used as a format string or template:
  `printf`-style formats, Python `str.format` (a user-controlled format
  string can read object attributes), `String.format`, logger message
  templates. Pass it as an argument.
- INJ-14 [if DOCGEN] Document generators are interpreters. LaTeX MUST run
  with shell escape disabled (`-no-shell-escape`) and restricted file access
  (`openin_any = p`, `openout_any = p`), with user text escaped for LaTeX
  special characters. HTML-to-PDF converters receive escaped HTML and
  follow EXT-22.
- INJ-15 [if USER_CODE] User-supplied code (formulas, scripts, rules,
  plugins) MUST NOT run in the application process. Use a purpose-built
  evaluator with a fixed grammar (for example a formula parser), or a
  separate sandboxed process with no network, no filesystem access and CPU,
  memory and time limits. Language-level sandboxes (Node.js `vm`, restricted
  `eval`) are not security boundaries.

### 11.3 Output to browsers

- INJ-16 MUST rely on the framework's context-aware auto-escaping for
  HTML. Every bypass (`dangerouslySetInnerHTML`, `v-html`, `|safe`,
  `raw()`) MUST carry a review comment and use sanitized input (INJ-17).
- INJ-17 [if RICH_TEXT] Rich text MUST be sanitized server-side with a
  maintained allow-list sanitizer. Markdown MUST be rendered with raw HTML
  disabled, then sanitized.
- INJ-18 Values placed into HTML attributes, URLs, JavaScript, CSS or
  JSON embedded in HTML MUST use the encoder for that context.
- INJ-19 JSON embedded in HTML (`<script>` blocks, data attributes) MUST
  be serialized with `<`, `>`, `&`, U+2028 and U+2029 escaped, so that
  `</script>` cannot break out. No JSONP.
- INJ-20 Untrusted values MUST NOT go into inline scripts, event-handler
  attributes (`onclick`), `style` attributes or style sheets.
  URL-bearing attributes (`href`, `src`, `action`, `formaction`) take only
  encoded, scheme-checked URLs (WEB-14).
- INJ-21 Client-side template injection: user text MUST NOT reach a
  front-end framework's template compiler (for example `{{ }}` in
  server-rendered HTML that the framework then compiles); render it as
  text.
- INJ-22 [if RICH_TEXT] Sanitize last: HTML sanitization MUST run after
  every other transformation (Markdown rendering, truncation, link
  rewriting, mention expansion). Changing sanitized HTML afterwards reopens
  injection (mutation XSS).

### 11.4 Headers, logs, exports and outbound requests

- INJ-23 Headers, cookies and redirect locations MUST be set through
  framework APIs; raw CR and LF MUST be rejected (response splitting).
- INJ-24 Logs MUST be structured, with untrusted values encoded (log
  injection).
- INJ-25 [if IMPORT_EXPORT] CSV and spreadsheet exports MUST neutralize
  cells that begin with `=`, `+`, `-`, `@`, tab or carriage return (formula
  injection).
- INJ-26 Logging MUST NOT evaluate lookups or expressions inside messages
  (Log4Shell-style `${...}`). User values go in as structured fields,
  never as the message template (INJ-13).
- INJ-27 [if OUTBOUND_HTTP] User values in the URL path, query or headers of
  an outbound request MUST be encoded by the URL and header builders (path
  segments escaped, CR and LF rejected), so that they cannot change the
  target path (`../admin`), the query or the headers of a vendor call.

### 11.5 Canonicalization

- INJ-28 Validate after canonicalization: decode input exactly once
  (percent-decoding, Unicode normalization to NFC or NFKC), then validate
  the result. Reject double-encoded input, NUL bytes and invalid UTF-8.
- INJ-29 Any file path built from data (archive entries, stored names,
  configuration) MUST be resolved (`realpath`) and checked to stay inside
  its base directory before use (AUTHZ-15, FILE-09).
- INJ-30 Source files MUST NOT contain Unicode bidirectional control
  characters or invisible characters (Trojan Source). Check generated code
  for them before committing.


## 12. Browser security, CSRF and front-end code (WEB)

### 12.1 Headers and cookies

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

### 12.2 Cross-site request forgery (CSRF)

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
- WEB-11 [if REALTIME] WebSocket upgrades MUST check `Origin` against an
  allow-list and authenticate the connection (cross-site WebSocket
  hijacking). Each message type MUST be authorized (AUTHZ-05).
- WEB-12 CORS MUST NOT be treated as a CSRF defense; it governs reading
  responses, not sending requests.

### 12.3 Front-end code

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


## 13. API design (API)

- API-01 Every request MUST be validated against a schema (OpenAPI, JSON
  Schema or typed DTOs). Unknown fields MUST be rejected.
- API-02 [if PUBLIC_API] Responses SHOULD be validated against the schema in
  tests.
- API-03 Limits MUST exist for body size, array length, nesting depth,
  string length, page size and query time (DOS-01..03).
- API-04 [if GRAPHQL] GraphQL MUST enforce depth, cost, alias and batch
  limits. Introspection SHOULD be disabled for public production clients,
  which SHOULD use persisted queries.
- API-05 Rate limits MUST exist per user, per account and per client IP,
  stricter for unauthenticated and expensive endpoints (DOS-05).
- API-06 Errors MUST use one format, without stack traces, SQL, file
  paths, internal hostnames or library versions.
- API-07 Redirect targets (`next`, `return_to`, `redirect_uri`) MUST be
  relative paths or match an allow-list exactly (open redirect).
- API-08 Duplicate query parameters and duplicate JSON keys MUST be
  rejected, or handled by one documented rule in every layer (parameter
  pollution).
- API-09 [if PUBLIC_API] Deprecated API versions MUST keep every security
  control until they are removed.
- API-10 [if PUBLIC_API] Every endpoint MUST appear in the API
  specification. Undocumented ("shadow") endpoints MUST NOT exist.


## 14. Files and uploads (FILE) [if UPLOADS]

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
- FILE-08 [if UPLOADS or DOCGEN] Image, PDF and office-document processing
  MUST run in an isolated worker with CPU, memory and time limits.
- FILE-09 Archive extraction MUST reject absolute paths, `..` segments and
  symlinks (zip slip), and MUST enforce limits on entry count, total size
  and compression ratio.
- FILE-10 Download URLs MUST be short-lived signed URLs, issued after
  authorization (AUTHZ-13).


## 15. Cryptography (CRY)

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


## 16. Parsers, serialization and HTTP-level traps (PARSE, HTTP)

### 16.1 Parsers and serialization

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

### 16.2 HTTP-level traps and exposed internals

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


## 17. Denial of service at the application level (DOS)

Volumetric DDoS is absorbed in front of the app and is out of scope. The
code decides whether one cheap request can trigger expensive work.

### 17.1 Bound every request

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

### 17.2 Expensive operations and fairness

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

### 17.3 Parser and content bombs

- DOS-09 Decompression MUST cap output size and compression ratio
  (archives and compressed request bodies). Image decoding MUST check
  pixel dimensions before decoding (pixel floods). See also PARSE-01,
  PARSE-04, PARSE-06 and FILE-09.

### 17.4 Queues, retries and caches

- DOS-10 [if JOBS] Queues MUST be bounded, with backpressure. Jobs MUST have
  timeouts and a maximum attempt count; failures go to a dead-letter
  queue.
- DOS-11 Retries MUST use exponential backoff with jitter and a retry
  budget. MUST NOT retry 4xx responses, except 408 and 429 with backoff.
  Circuit breakers SHOULD protect every vendor.
- DOS-12 Our own clients (web app, SDKs, mobile apps) MUST back off on
  `429` and `503`.
- DOS-13 [if CACHE] Caches SHOULD coalesce concurrent misses (single-flight)
  and jitter TTLs, and MAY serve stale data on error.
- DOS-14 Repeated identical errors SHOULD be aggregated rather than logged
  one by one; log volume per request SHOULD be bounded.

### 17.5 Long-lived connections [if REALTIME]

- DOS-15 WebSocket and server-sent-event connections MUST have per-user
  connection limits, message size and rate limits, heartbeats, idle
  timeouts, and re-authentication when the token expires.

### 17.6 Scaling and health checks

- DOS-16 [if MULTI_PROCESS] Application servers MUST be stateless (sessions
  in a shared store), so they scale horizontally.
- DOS-17 Liveness checks MUST NOT touch external dependencies. Readiness
  checks MUST use short timeouts.
- DOS-18 Account lockout MUST NOT be usable for denial of service
  (AUTHN-07).

## 18. Secrets, configuration, build and CI (SEC, CFG, CI)

### 18.1 Secrets

- SEC-01 Secrets MUST be loaded at runtime from a secret manager, or
  injected by the platform. They MUST NOT appear in the repo, container
  images, client bundles, logs, error messages, test fixtures, CI output
  or build arguments.
- SEC-02 [if CI] CI MUST authenticate to cloud services through OIDC
  federation, and the app SHOULD use workload identity. No static cloud
  keys.
- SEC-03 The app MUST support key rotation without downtime: accept the
  current and the previous signing or decryption key during a rotation
  window, and reload secrets without a restart.
- SEC-04 Each environment MUST have its own secrets. Nothing is shared
  between staging and production.
- SEC-05 Anything sent to the browser is public. Only publishable keys may
  ship to clients.

### 18.2 Configuration and container image

- CFG-01 Configuration MUST be typed and validated at startup. Defaults
  MUST be the secure option, so a missing setting is the safe one.
- CFG-02 In production mode the app MUST refuse to start if: debug is on;
  a secret is empty or a known default; CORS is permissive; TLS settings
  are missing; sandbox or test vendor credentials are configured; or a
  required security setting is absent.
- CFG-03 Production builds MUST NOT contain default accounts, sample apps,
  seed users or test routes. The first admin MUST be created with a
  one-time setup token.
- CFG-04 [if CONTAINERS] Container images MUST use a minimal base image
  pinned by digest; a multi-stage build without compilers or package
  managers in the runtime stage; a non-root user; compatibility with a
  read-only root filesystem; no secrets in layers or build arguments; a
  `.dockerignore` that excludes `.git`, `.env` and local artifacts.
- CFG-05 Local development MUST use fake vendors and synthetic data.
  Production data and credentials MUST NOT be used on developer machines.
- CFG-06 Development, test and production MUST share one configuration
  schema, with different values and credentials.

### 18.3 CI and build files [if CI]

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


## 19. Logging, audit trail and kill switches (LOG)

### 19.1 Logs

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

### 19.2 Audit trail

- LOG-06 The audit trail MUST be separate from debug logs, append-only and
  tamper-evident (write-once storage or a hash chain).
- LOG-07 Audit records MUST capture who, what, when (UTC), from where,
  and before/after values for: sign-ins; MFA and recovery changes; role
  and permission changes; access denials on sensitive resources; exports;
  impersonation; configuration changes; API key lifecycle; money
  movements.
- LOG-08 The audit trail MUST make it possible to tell which users and
  which data an actor touched in a given time window.

### 19.3 Security events

- LOG-09 The app MUST emit named `SecurityEvent`s, so operations can alert
  without reading code, for at least the following, where the feature
  exists: failed logins; OTP sends and
  failures; password resets; spikes of object-ID 404s per actor
  (enumeration); SMS verify rate per country; SMS budget exhausted;
  webhook signature failures; new platform admin; role grants (admin
  above all); impersonation start; mass export; rate-limit and quota
  rejections; error rate; queue depth; dead-letter growth; vendor latency
  beyond its timeout budget.

### 19.4 Kill switches

- LOG-10 Kill switches MUST exist and be covered by tests: revoke the
  sessions of one user, and of all users.
- LOG-11 Secrets MUST be hot-reloadable (SEC-03), so a leaked key can be
  rotated without a deploy.
- LOG-12 [if API_KEYS] A kill switch MUST invalidate all API keys of a user.
- LOG-13 [if OUTBOUND_HTTP or WEBHOOKS_IN] A kill switch MUST disable each
  third-party integration on its own.


## 20. Personal data (PRIV)

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


## 21. Design review and testing (TEST)

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
  - privilege escalation: each path in AUTHZ-23 is attempted and fails,
    and a revoked role or grant stops working on the next request;
  - domain rules: invariants, state transitions, money and time
    arithmetic, with property-based tests where inputs vary widely;
  - database: constraints, row-level security if used, and migrations
    from empty and from N-1 to N, against a real database;
  - concurrency: parallel requests against every security limit,
    single-use token and idempotent operation produce exactly one effect
    or stay within the limit (STATE-02, STATE-03);
  - caches and replicas [if CACHE or REPLICAS]: a revoked session, role or
    grant is rejected immediately, on every instance and on every read path;
  - read-only mode [if READ_ONLY_MODE]: every writing handler and job is
    refused, while throttles, revocations and audit records are still
    written;
  - webhooks and vendors [if OUTBOUND_HTTP or WEBHOOKS_IN]: bad signature,
    stale timestamp, replayed event, vendor timeout, malformed response;
  - sign-up abuse [if SIGNUP]: repeated sign-ups for one address, after the
    pending sign-up expires and with `+tag` or dot variants, send no more
    messages than MSG-16 allows, and a suppressed address gets none;
  - security regressions: CSRF token and `Origin` checks, SSRF block
    list, headers, cookie flags, upload type checks, fail-to-start
    configuration, kill switches, rate limits and quotas;
  - parsers and file handlers: malformed and hostile input (fuzz where a
    fuzzing harness exists).
- TEST-04 Security tests MUST NOT be skipped, marked flaky or deleted
  without a replacement and a reason in the commit message.


## 22. OWASP Top 10:2025 coverage

| Category | Covered by |
| --- | --- |
| A01 Broken Access Control (includes SSRF and CSRF) | ISO, AUTHZ, DATA, WEB-05..12, EXT-17..23 |
| A02 Security Misconfiguration (includes XXE) | CFG, WEB-01..06, HTTP-04, PARSE-01 |
| A03 Software Supply Chain Failures | AI-01, CI |
| A04 Cryptographic Failures | CRY, SEC, AUTHN-03 |
| A05 Injection (includes XSS) | INJ, WEB-13..16, PARSE |
| A06 Insecure Design | PRIN, BIZ, STATE, TEST-01, DOS |
| A07 Authentication Failures | AUTHN |
| A08 Software or Data Integrity Failures | CI-02, CI-03, PARSE-03, EXT-12..16, STATE-23 |
| A09 Security Logging and Alerting Failures | LOG |
| A10 Mishandling of Exceptional Conditions | BIZ-10..14, DOS-10..14 |


## 23. Before committing

Skip the items whose rules do not apply under the project's conditions
(section 0.5).

- [ ] Threat-model questions answered where required (TEST-01)
- [ ] Every new route, resolver, RPC method, job and socket handler has a
      policy and authorization-matrix rows (AUTHZ-05, AUTHZ-16)
- [ ] Data access only through `DataAccess`; IDOR test added (DATA-01,
      TEST-03)
- [ ] New stores, keys, channels and files are namespaced by owner, and
      every referenced object is authorized (ISO-03, ISO-13)
- [ ] Requests schema-validated; writable fields allow-listed; response
      DTOs used (API-01, AUTHZ-08, AUTHZ-09)
- [ ] New permissions are assigned to roles explicitly, and nothing lets
      a user grant more than they hold (AUTHZ-18, AUTHZ-23)
- [ ] New state-changing endpoints CSRF-protected; no GET side effects
      (WEB-07, WEB-08)
- [ ] New endpoints have size, rate, page-size and time limits; expensive
      work async with per-user quotas (DOS-01..08)
- [ ] User-controlled URLs go through `EgressClient`; egress list updated
      (EXT-17, EXT-25)
- [ ] Every interpreter (database, shell, template engine, document
      generator, logger) gets untrusted data only as parameters,
      arguments or encoded values (INJ)
- [ ] Output encoded for its context; no unsafe DOM sinks (INJ-16..18,
      WEB-13)
- [ ] New invariants backed by constraints; state changes through
      transition functions (BIZ-02, BIZ-07)
- [ ] Retryable mutating endpoints accept an idempotency key, scoped to
      the actor (STATE-08, STATE-10)
- [ ] Security limits and single-use tokens are enforced atomically
      (STATE-02, STATE-03)
- [ ] Cache keys include the actor where the value depends on it, and
      security changes invalidate them (STATE-22, STATE-25)
- [ ] New handlers declare whether they read or write, and reading
      handlers have no side effects (STATE-34, STATE-35)
- [ ] External calls have timeouts and bounded retries, and run outside
      database transactions (EXT-02, EXT-03, EXT-05)
- [ ] Errors fail closed; nothing swallowed; resources released on error
      paths (BIZ-10, BIZ-13)
- [ ] No secrets, tokens, OTPs or personal data in code, logs, errors or
      fixtures (SEC-01, LOG-03)
- [ ] Security-relevant actions write audit records and emit security
      events (LOG-07, LOG-09)
- [ ] New dependency justified and verified; lockfile updated (AI-01,
      CI-03)
- [ ] Tests written from the specification, including misuse cases; bug
      fixes start with a failing test (AI-05, BIZ-15, TEST-02)
- [ ] Migrations backward compatible (DATA-08)


## 24. References

- OWASP Top 10:2025: https://top10.owasp.org/2025/
- NIST SP 800-63B-4 (Digital Identity Guidelines, Authentication):
  https://pages.nist.gov/800-63-4/sp800-63b.html
- Twilio, preventing SMS pumping fraud:
  https://www.twilio.com/docs/messaging/guides/preventing-messaging-fraud
- Cloud Security Alliance, slopsquatting research note (April 2026):
  https://labs.cloudsecurityalliance.org/research/csa-research-note-slopsquatting-ai-supply-chain-20260419/
