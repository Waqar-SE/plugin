# Backend Style Guide

> Paths verified against SimpliHost commit `5a485fefb` on 2026-10-13 with `scripts/check-guide-paths.sh`. Record a rule the code does not follow in the PR body under **Review > Guide drift**; update this guide in the plugin repository.

Rules for the Django backend in `src/` (paths relative to `src/`), written for the developer or
coding agent making the change. Reference implementations: `integrations/runited` (with
`workers/rentalsunited.py`), `integrations/seamdevices`, `integrations/pricelabs`. Process
(branches, commits, PRs) is in `CONTRIBUTING.md` at the root of the repository.

## 0. Before you write code

1. Read `src/<app>/CLAUDE.md` for every app you touch (`properties`, `workers`, `devices`,
   `inventory`, `integrations/runited`, `integrations/seamdevices`). They hold invariants the code
   doesn't show (units, timezones, dedup lanes).
2. Search for an existing entry point before adding one: `<app>/services/__init__.py`,
   `<app>/selectors*`, `common/mixins.py`, `common/utils.py`, `common/api/serializers.py`,
   `common/admin.py`, `workers/utils.py`, `workers/event_router.py` (`EventRegistry.mappings`).
   Extend the existing method; don't add a parallel sibling.
3. Find the closest existing feature and copy its shape (layout, names, tests), except a
   static/class-method service class: write module functions instead (§2).
4. Trace every caller of what you change; fix the shared function, not one path.
5. Decide the test first (§20); know which `TEST_SUITE` entry it goes in.

## 1. Tooling and commands

- Ruff lint + format, **79-char lines**, isort `force-sort-within-sections`, `add-trailing-comma`.
  Module docstring first; no `breakpoint()`/`pdb`. Let the formatter win.
- pre-commit runs Ruff, hygiene hooks and `makemigrations --check`; install it per clone
  (`pre-commit install --hook-type pre-commit`).
- Dependencies via pdm (`pyproject.toml` + committed `pdm.lock`). Add one only when nothing
  installed covers it; never hand-edit the lock.
- Ruff options go in the sections Ruff currently documents (lint rules under `[tool.ruff.lint]`);
  a lint run prints no configuration warnings.
- `--keepdb` reuses a test database at its old migration state. After migrations are rewritten
  or renumbered (errors like "column … does not exist" or "already exists"), point
  `DATABASE_URL` at a fresh database name instead of chasing the error.

```bash
python manage.py test <app_or_dotted_path> --keepdb
ruff check src --fix && ruff format src
python manage.py makemigrations --check --dry-run
pre-commit run --all-files
```

## 2. Layout and layering

```
<app>/
  models.py | models/   choices.py   exceptions.py   signals.py   admin.py   CLAUDE.md   validators.py
  selectors.py | selectors/       services.py | services/  (exported from services/__init__.py)
  api/{serializers,viewsets,urls,filters,permissions}.py   management/commands/   tests/
integrations/<provider>/   # adds, see §21
  client.py  adapters/{inbound,outbound,tolerant,constants}.py | adapters.py
  api/{authentication,parsers,webhooks}.py  webhooks/{dispatcher,registry,base,events}.py + handlers/
  dictionaries.py  *_mappings.py  notifications.py  utils.py
```

Celery tasks live **only** in `workers/<area>.py`; task-side helpers in `workers/services/<area>.py`.

| Layer | Owns | Never |
| --- | --- | --- |
| Viewset / webhook | auth, (de)serialization, **one** service call | loops with rules, manual syncs |
| Serializer | data shape, field validation | orchestration, business rules |
| Service | business rules, writes, transactions, event dispatch | — |
| Selector | querysets and read models (incl. outbound payloads) | writes |
| Adapter | provider payloads ⇄ service data, unit/format/status conversion | business rules |
| Client | provider transport, logging hook, error decoding | — |
| Model | fields, constraints, cheap `@property` | orchestration, stored derived values |

- A service owns the **whole** flow, including external syncs, so no caller can forget a step; it
  runs the same from a view, task, command or shell.
- Business validation raises DRF `ValidationError` from the service.
- One named writer per piece of state, stated in its docstring (`push_property` is the only writer
  of `RUProperty.owner`).
- Services are module-level functions (`ingest_reservation_data`), following the Google Python
  Style Guide (no `@staticmethod`; `@classmethod` only for alternate constructors), Python idiom
  (the module is the namespace) and the Django service-layer style (one function per operation,
  keyword-only arguments: `def hold_captured(*, request, charge_id)`). Callers import the module
  and call `transactions.hold_captured(...)`; private helpers are `_` module functions.
- Never a class made only of `@staticmethod`/`@classmethod` methods
  (`TransactionLogService.hold_captured` is the shape to stop copying). A class is allowed only
  when it holds real per-object state that several methods read
  (`PaymentScheduleService(reservation)`); state passed to a single call is an argument.
- New code follows this even where the app still uses namespace classes. Adding to an existing
  namespace class inside a ticket: write a module function next to it, and don't convert the class
  in the same PR (follow-up). Split a service or viewset that mixes responsibilities.
- Logic shared by a worker and a webhook lives once in a service both call.
- Selectors: module functions, same rules as services.
- Dependency direction is integration → domain; the domain knows an integration only by reverse
  names (`Device.seam_link`). A domain app (`properties`, `accounts`, `billing`) never imports an
  integration's models, services or selectors; `workers/` and `integrations/*` import the domain.
  Existing imports the other way are debt, not precedent: a new one is a finding even where the
  app already has some.
- Each separately served surface of an app (admin API, public pages) gets its own
  sub-package like `api/` (`<app>/<surface>/urls.py`, `views.py`), never `<surface>_urls.py` /
  `<surface>_views.py` at the app root.
- Code several surfaces use stays out of any one surface's package, and dependencies point from
  the narrower surface to the shared code, never back.
- Don't move routes to a new file that the parent `urls.py` must still `include()`; collapse a
  repeated prefix in place with `path("prefix/", include([...]))`.

## 3. Models

- Extend `common.models.BaseModel` (`created_at`, `updated_at`, `is_deleted`, ordering `-id`);
  plain `models.Model` only for append-only rows (`integrations.Log`). Provider config extends
  `integrations.models.Integration`. A model that declares `Meta` subclasses `BaseModel.Meta`.
- Cross-app FKs by string (`"accounts.Company"`) with `related_name`. FK to Property is
  `property_object`. Tenant-owned rows carry `company` (directly or via a parent).
- Optional text: `blank=True, default=""`; `null=True` only when NULL means something, said in a
  comment. Every model has `__str__`.
- Store raw values in our units; never store derived data (occupancy, totals) or converted copies.
- `save(update_fields=[...])` and `queryset.update(...)` include `updated_at`.
- `QuerySet` subclass + `.as_manager()` when every reader/writer must narrow the same way.
- Provider ids live on an integration-owned link model (`SeamDeviceLink`, `RUProperty`).
- Reusable field validators live in `<app>/validators.py` (`accounts/validators.py`), never in
  `models.py`; models, serializers and services import them from there. Moving a `RegexValidator`
  changes no migration; confirm with `makemigrations --check`.

### App ownership

- An integration app holds only provider-specific data: external ids, raw provider statuses,
  sync bookkeeping, credentials. A fact the host cares about independent of the provider (which
  channels a property is listed on, whether each is on or off, who changed it and when, the audit
  of that change) lives on a domain model, written by the integration through a service.
- Test: if the provider were replaced tomorrow, would the field have to be migrated back into the
  domain app? Then it is in the wrong app.
- Design the domain model against this rule. A reference branch given for its API code lends its
  request and parse code only, never its model shape.
- A field, table or app placement that a work item or a design document leaves to a named person
  ("Dev lead to set", "Owner: Beth") is not the planner's to decide: it is a `blocking` question.

### Choices

- In `<app>/choices.py`; compare against the enum, never a literal. Lowercase values with labels.
- Provider codes keep the provider's value verbatim (`RUErrorCode.RATE_LIMITED = "-6"`), grouped
  in a `frozenset` (`RU_RATE_LIMIT_ERROR_CODES`). Provider lookup constants live here too.
- If a flow branches on a provider enum, handle every documented value, not only those seen.

### Invariants and soft delete

- "Should never happen" is a constraint: `UniqueConstraint` (`condition=` for one-active /
  one-default, `Lower(...)` for case-insensitive), `CheckConstraint`; never `unique_together`.
  snake_case names stating the rule (`unique_default_owner_per_account`).
- Idempotency is a unique row, not a lookup. M2M rows that carry data use a through model.
- Audit-relevant rows are soft-deleted. There is no filtering manager: **every reader filters
  `is_deleted=False`**, including public and webhook lookups; partial unique constraints are
  conditioned on it.

## 4. Multi-tenancy and permissions

- Scope every queryset to `request.user.current_company` in `get_queryset` (or its selector), then
  use `get_object()` — never `get_object_or_404` + a manual access check. A cross-company id is
  **404**. Serializer related-field querysets are company-scoped. Authorization is on `Profile`
  (`request.user.current_profile`), not `User`.
- Hidden fields: `CurrentCompanyDefault` / `CurrentProfileDefault` (`common/api/serializers.py`).
- Codenames: `EnforcePermissionsMixin` + `required_permissions` (method → codename) and/or
  `action_permissions` (action → codename, required **in addition to** the method's). Lists are
  any-of. A method without an entry is allowed, so declare one for every method and action; a
  view with neither dict raises `ImproperlyConfigured`.
  ```python
  class PriceLabAccountViewSet(EnforcePermissionsMixin, GenericViewSet, ...):
      required_permissions = {"GET": "view_pricelabintegration"}
      action_permissions = {"pull": "pull_pricelabs", "publish_all": "push_pricelabs"}
  ```
- Add classes via `AppendPermissionsMixin.extra_permission_classes`. Never assign
  `permission_classes` on an authenticated view (it drops `IsAuthenticated`,
  `HasValidSubscription`, `ImpersonationReadOnly`), except:
  - webhooks and public endpoints (own auth, §5, §21);
  - billing views that must work without a valid subscription
    (`[IsAuthenticated, IsAccountAdminPermission]`);
  - a custom permission class that is the sole gate of its viewset (`CalendarAPIPermission`),
    never combined with `EnforcePermissionsMixin`.
- Admin-only areas use `IsAccountAdminPermission` (`common/permission.py`).
- Never return secrets: mask in the serializer (`MASKED_PASSWORD`), unmask only behind the
  codename; mask financial fields with `FinancialFieldsMixin` / `profile_has_permission`.
- If a 403 is wrong, fix the client's call or expose a narrowly-scoped action that checks the
  flow's existing codename — never grant a broader codename.
- New codenames are seeded by data migration via `seed_permission_registry(apps=apps)`.

## 5. API design (DRF)

- Resources: plural kebab-case nouns under `/api/<app>/`, `basename="<app>-<resource>"`; verbs only
  as `@action` (kebab-case `url_path`) on router-registered viewsets. No versioning.
- `GenericViewSet` + only the mixins you need; `http_method_names` without PUT.
  `get_serializer_class()` picks list / detail / `*WriteSerializer`.
- Pagination `LinkHeaderPagination`, 100/page; `pagination_class = None` only with a comment.
  Filtering via django-filter `filterset_class` (invalid values 400); `StableOrderingFilter` for a
  pk tiebreaker.
- Serializer fields: prefer `source=`, `ReadOnlyField(source="get_x_display")`, `SlugRelatedField`;
  `SerializerMethodField` only for fallbacks or computations over prefetched rows. Field rules in
  `validate_<field>`, cross-field in `validate()` reading `attrs`. Inbound provider serializers keep
  provider field names (`ReservationID`).
- The field's own checks (required, blank, `max_length`, format) run **before**
  `validate_<field>`, so a message for them written there never shows. Put it on the field:
  `error_messages={"blank": ..., "max_length": ...}`, declared or via `Meta.extra_kwargs`.
  `validate_<field>` is for rules the field can't express (per-company uniqueness, digit counts).
- `CharField`, `EmailField` and `SlugField` trim whitespace by default: no `validate_<field>`
  that only returns `value.strip()`, and no `.strip()` inside one that checks something.
- `ModelSerializer` copies `max_length`, `allow_blank` and `allow_null` from the model; don't
  restate them in `extra_kwargs`. A field the model allows blank (the save fills a default) but
  the API requires gets `{"allow_blank": False, "error_messages": {"blank": ...}}`, not an
  `if not value` check.
- Status codes: 200/201/204 success; 400 invalid input; 402 subscription (`HasValidSubscription`);
  403 permission; 404 missing or cross-company; 409 state conflict / stale save; 502 provider.
- Response fields are a contract with web and mobile clients: add freely; rename or remove only
  once no client reads them, and then everywhere (serializer, selectors, frontend).
- Schema (drf-spectacular): `@extend_schema(request=..., responses=...)` on custom actions and
  `APIView`s; when the serializer varies per action, name it there and use `self.get_serializer()`.
  Shared enums get an `ENUM_NAME_OVERRIDES` entry.
- Public endpoints: `authentication_classes = []`, `AllowAny`, and a scoped `SimpleRateThrottle`
  with its rate in settings (`directbooking/api/public.py`).

### Errors and copy

- Services raise DRF exceptions for request errors. A domain failure a caller must branch on is a
  plain `Exception` subclass with a docstring next to the service (`StripeAccountAlreadyLinked`);
  the view maps it.
- Error body: `{"detail": ..., "code": ...}` or field → messages. 409s are `APIException`
  subclasses in `<app>/exceptions.py` with a machine-readable `code`; assign `self.detail` after
  `super().__init__()` when the payload holds ints/ids.
- Provider refused/unreachable → 502 with a user-written message (no credentials, no raw body).
- Stale-save checks are mandatory: the client sends what it loaded (`updated_at`/`version`).
- User-facing messages are module constants (`STALE_EDIT_MESSAGE`, `REFUND_FAILED`): what happened
  and what to do, sentence case, a period; no ids, exception text or provider jargon.

## 6. Transactions, locking, caching

- Multi-step writes (including delete-then-create) in `transaction.atomic()`.
- Read-check-write under `select_for_update()`, re-checking state after the lock:
  ```python
  with transaction.atomic():
      current = Model.objects.select_for_update().get(pk=row.pk)
      if expected_updated_at is not None and current.updated_at != expected_updated_at:
          raise Conflict({"detail": STALE_EDIT_MESSAGE})
  ```
- Lock the parent row to serialize "first one wins" across children. Check-then-create against a
  unique constraint catches `IntegrityError` → attach or 409, never 500.
- A pending or in-flight flag (`pending_request`, `status="pending"`) is a read-check-write: two
  users who flip the same switch in the same second both pass the check and create two requests.
  Lock the affected rows and re-check inside `atomic()`, or make the flag a partial unique
  constraint (`condition=Q(status="pending")`).
- Side effects that must not survive rollback go in `transaction.on_commit`
  (`enqueue_if_not_pending` already defers itself).
- Commit local state only after the provider accepted the change.
- Cache (Redis) holds short-lived, rebuildable values only. A lock with no row to lock is
  `cache.add(key, True, timeout=...)` released in `finally` (`directbooking/services/review.py`).
  Per-request memoization is `cached_property` on a selector class.
- A cached page or lookup is keyed so a save invalidates it: include the row's `updated_at`
  (`<area>:{id}:{updated_at}:...`), or delete the key in the service that writes the row.

## 7. Celery and events

- `@shared_task(bind=True)` in `workers/<area>.py`; `CustomTask` is the app's `task_cls` (pass
  `base=` only for a subclass with lifecycle hooks). A new module goes in `CELERY_IMPORTS`; route
  queues in `CELERY_TASK_ROUTES`.
- Take ids, **always accept `**kwargs`**, return nothing. Idempotent: re-read state, exit early.
- Expected data failures: `raise TaskFailure() from exc` (`workers.exceptions`, no retry).
  `CustomTask` autoretries `TRANSIENT_EXCEPTIONS`; rate limits `raise self.retry(exc=exc,
  countdown=60)`, then `TaskFailure`.
- Dispatch only via `enqueue_if_not_pending(task, f"{model}:{id}", kwargs=...)`, where `{model}` is
  the id's model; suffix for an independent lane (`f"property:{id}:content"`), `countdown=` for a
  delay. Ordered steps: `chain(a.si(id), b.si(id))` inside a task. No `.delay()`/`send_task()`; no
  assumed ordering between tasks.
- Side effects of a change: add or extend an `EventRegistry.mappings` entry (filter by `fields`,
  `actors`, `model_state`, `conditions` such as `first_push=True`), then fire it from the service:
  ```python
  router = EventRouter(instance)
  router.register_event(Actors.SIMPLIHOST.value, "model:updated", {"field": value})
  router.dispatch_events()
  ```
  Pass the actor that caused the change (`Actors.RENTALS_UNITED` for inbound RU) so it isn't echoed
  back. Never call a task from a view.
- `register_event` / `dispatch_events` run inside the service, after its guards and writes, never
  in `perform_create` / `perform_destroy` beside the service call: a refused request (400) must
  leave no `Event` row behind.
- Beat entries in `CELERY_BEAT_SCHEDULE` with a comment justifying frequency. Every task loop over
  accounts, owners, properties or rows, including one-off release tasks and management commands,
  wraps each item in `try/except` + `logger.exception`: one item's provider error must not stop
  the rest.

## 8. Signals

- Rare; prefer services + `EventRouter`. Register in `AppConfig.ready` with a `dispatch_uid`.

## 9. Settings, time, logging

- Env vars only in `simplihost/settings.py`, declared with type and default in `environ.Env(...)`;
  elsewhere `django.conf.settings`. Tunables are settings with a unit comment
  (`ENHANCED_IMAGE_TTL`); environment branches live only in `settings.py`.
- Required production secrets fail a system check (`directbooking/checks.py`); code reading a secret
  fails closed when unset. SDK globals are set once in `AppConfig.ready` (`StripeConfig`).
- UTC everywhere (`timezone.now()`); property-local dates via `get_property_tz` /
  `get_property_local_today` (`properties/utils.py`). A provider clock gets a constant + helper
  (`RU_TIMEZONE`, `ru_today()`); a clock tests freeze is a module function (`current_time()`).
- `logger = logging.getLogger(__name__)`, lazy `%s` args. RU tasks use `get_ru_logger(logger,
  ru_account)`. `logger.exception` in `except`; `logger.critical` when a human must act.
- Broad `except Exception:` only where failure is deliberately contained, with a comment why. No
  `print()` outside management commands.

## 10. Security

- Validate every external input with a serializer or pydantic adapter; frontend validation is UX
  only. Never trust company, ids or amounts from the payload over the scoped queryset.
- Every endpoint has explicit authentication; signed webhooks use a DRF authentication class.
- ORM only; raw SQL (`connection.cursor()`) only when the ORM can't express it, always
  parameterized.
- Secrets live in settings, never in code, fixtures, `Log` rows or error messages; compare them with
  `constant_time_compare`.
- No PII (guest emails, phones, card data, tokens) in log messages — log ids.
- HTML via `format_html` / templates; `html.escape` user values in generated email bodies.
- A secret in a URL (token, signed link) leaks through `Referer` to every third party the page
  loads. Those responses set a stricter `Referrer-Policy` (`strict-origin-when-cross-origin`),
  assigned directly (`response["Referrer-Policy"] = ...`; `SecurityMiddleware` only uses
  `setdefault`).
- A security setting one surface needs differently is overridden on that surface's responses,
  never changed globally: other flows depend on the global value (`SECURE_REFERRER_POLICY` is set
  for Google OAuth).
- The client IP comes only from DRF's throttle `get_ident()` (or a helper built on it), never
  `X-Forwarded-For` or `REMOTE_ADDR`. `DRF_NUM_PROXIES` equals the number of proxies that append to
  `X-Forwarded-For` in that environment: too low and every visitor shares one throttle bucket, too
  high and the client can spoof its IP. A change to the proxy chain changes this setting.
- Public content customers write (text, images, links) shares the reputation of the domain it is
  served from; a scam on it can get that domain blocklisted. Serving it under `simplihost.com` is
  a decision to raise, not a default. Never put `simplihost.com` on the Public Suffix List.
- Never add a wildcard to `ALLOWED_HOSTS`: every made-up name would reach the whole app. Extra
  hosts are validated in middleware, which limits them to their own routes (`request.urlconf`).
- Middleware that rewrites the host rewrites `HTTP_X_FORWARDED_HOST` too (Django reads it under
  `USE_X_FORWARDED_HOST`) and a same-origin `Origin` (the CSRF check compares it with the host).
  Afterwards `get_host()` / `build_absolute_uri()` return the rewritten host, so public URLs are
  built from the original one.
- Links that grant access without a login are `django.core.signing` tokens with their own salt,
  bound to the object and expiring. Their pages are `noindex` and stay out of shared caches, and
  every action the link must not allow is refused on the server, not only hidden in the UI.

## 11. Query performance

- No queries in loops: `select_related` / `prefetch_related` (named `Prefetch`) in `get_queryset`
  or the selector; serializer methods read only prefetched data.
- A scheduled task loads the rows it needs once per run (per account, per channel) and decides in
  memory. Multiply any per-item query by the item count, the account count and the schedule
  frequency before accepting it: four queries per property per channel every 10 minutes is a
  finding.
- Counts/sums via `annotate` / `aggregate` (`Count(..., filter=Q(...), distinct=True)`).
- Bulk writes via `bulk_create` / `bulk_update(batch_size=...)` / `queryset.update` — they skip
  `save()` and signals, so guards go on the QuerySet. `.iterator()` for large reads. Let
  `on_delete=CASCADE` do cleanup instead of loops.
- Index columns you filter or order by on large tables (`Meta.indexes` or a constraint).

## 12. Money and units

- `DecimalField(..., decimal_places=2)`; `Decimal(str(value))` from inputs, never `float`. Quantize
  to a named `CENT = Decimal("0.01")` with `ROUND_HALF_UP`.
- Minor units are named `*_cents` and converted only at the client boundary (`int(amount * 100)`).
- Currency is explicit (`company.preferred_currency`, or a `currency` field defaulting to `"usd"`).
- Display formatting in one helper (`fmt_money`, `directbooking/services/emails.py`).
- Provider units convert in the adapter with a named constant (`SQFT_PER_SQM`); store ours.

## 13. Email

- `django.core.mail.send_mail` with plain `message` **and** `html_message`, from
  `settings.DEFAULT_FROM_EMAIL` (or a dedicated setting such as `INBOX_FROM_EMAIL`).
- Fixed HTML in `templates/<app>/` via `render_to_string`, plain text via `strip_tags`. Host-editable
  copy is a model row with defaults in code (`EmailTemplate` + `email_defaults.py`).
- Sending belongs to a service (`DirectBookingEmailService`) run from a task or after commit;
  transactional emails record an outcome row (`EmailSendLog`). Tests assert on `mail.outbox`.

## 14. Websockets and notifications

- One consumer (`properties/consumers.py`, route `ws/`) in the per-user group `user_{user_id}`.
  Errors return `{"event": {"event_type": "error", "code", "detail"}}` and never reveal whether a
  foreign object exists.
- Background changes nudge screens with `trigger_refetch` + RTK Query tags from the app's
  `notifications.py` (`notify_smart_device_refetch`); tag lists are constants
  (`STRIPE_ACCOUNTS_TAGS`). Events carry no data — the client refetches through the API.
  ```python
  async_to_sync(channel_layer.group_send)(
      f"user_{user_id}",
      {"type": "send.event", "event_type": "trigger_refetch", "tags": ["Devices"]},
  )
  ```
- In-app notifications only via `accounts.services.NotificationService.notify` (row + WS nudge +
  push); a channel-layer failure is logged, never raised.

## 15. Files and storage

- Browser uploads go to S3 by presigned POST (`PreSignedPostURLMixin`,
  `common.utils.generate_presigned_post_url`, `AWS_MEDIA_BUCKET_NAME`); models store the URL
  (`URLField`), not a `FileField`.
- Server-side media writes take the same route (`properties/services/chat_media.py`), not
  `STORAGES`. Private reads use `generate_presigned_get_url`.

## 16. Django admin

- `@admin.register` with `list_display`, `list_filter`, `search_fields`; `raw_id_fields` /
  `autocomplete_fields` for large FKs; `list_select_related` or `get_queryset` with
  `select_related` + `annotate` for computed columns.
- Sync- or system-written fields are `readonly_fields`. Audit logs (`EmailSendLog`, `Log`) disable
  add/change/delete; code-created rows disable add.
- Actions: `@admin.action(description=...)` calling the service, reporting via `message_user`.
  Columns: `@admin.display(description=..., ordering=...)` + `format_html`. Reuse `CSVExportMixin`
  and `ObjectToolsMixin` (`common/admin.py`); filters subclass `SimpleListFilter`.

## 17. Management commands

- Operational tools only (setup, one-off repair, dev data); seeds and backfills are migrations.
- `help` says what it does. Data-changing commands take `--dry-run` and narrowing options
  (`--company`); reruns are safe (`populate` exits if populated).
- Reuse services/worker helpers, never copies (`repush_kwikset_access_codes`). Write via
  `self.stdout.write` + `self.style`, fail with `CommandError`, end with a summary.

## 18. Code style

- Names: service and selector functions are `verb_noun` in a module named for the area
  (`services/transactions.py::record_hold`); `<Noun>Service` only for a stateful class (§2);
  `<Noun>Adapter`; serializers `*List`, `*Detail`,
  `*Write`, `*Ref`; provider models prefixed (`RUOwner`). Name by intent. Private helpers `_`.
- Function-level imports only to break cycles, with a comment.
- Module constants sit right after the imports, before the first function or class. Ruff can't
  flag a constant further down (E402 covers imports only), so review does.
- A function does one thing; extract a named helper when a block needs a comment to say what it
  does. Long modules become a package (`services/`) or are sectioned with banners.
- Delete dead code completely — every reference in models, serializers, selectors, adapters,
  frontend and migrations, and every comment, docstring, `FIXME` or `CLAUDE.md` line that
  describes the removed thing. No commented-out code; no `TODO` without a tracked work item.
- Before deleting a domain field because an integration stopped writing it, ask whether the
  integration should still write it (§3 App ownership). A field in the right place with the wrong
  writer gets a new writer, not a deletion.
- Docstrings: first line says what, then *why*. Comments explain invariants and provider quirks.
  Type hints required on pydantic fields and dataclasses; otherwise follow the module.
- Invariants an agent can't see in code go in `<app>/CLAUDE.md`. A convention the code departs from
  is recorded in the PR body under **Review > Guide drift**; the guide is updated in the plugin repository.

## 19. Migrations

- One migration per change; squash WIP; renumber and fix dependencies when `main` moves.
- Seed/backfill in data migrations (`RunPython(forward, reverse)`), never in commands or test setup;
  comment when reverse can't restore data. Seeds freeze their data (no live app imports) except
  `seed_permission_registry` and seed functions taking historical models as arguments.
- Seeds are idempotent and insert-only (`get_or_create(..., defaults=...)`).
- Test non-trivial data migrations with `MigrationTestCase`.

## 20. Testing

- Register every new test module in `TEST_SUITE` (`settings.py`), or CI won't run it.
- **`PropertyBaseTestCase`** (`properties/tests/base.py`, an `APITestCase`): use it where you can.
  It builds `cls.company`, admin `cls.profile`/`cls.user` with an active subscription,
  `cls.property`, `cls.pricing`, platforms, inventories and amenity groups. Extend per app; add
  provider link rows in `setUpTestData`. Plain `TestCase` only when nothing needs a property.
- **`CaptureTasksMixin`** (`common/tests/mixins.py`) patches `enqueue_if_not_pending`; place it
  **before** the TestCase:
  ```python
  class IngestTestCase(CaptureTasksMixin, PropertyBaseTestCase):
      def test_dispatch_survives_commit(self):
          with self.captureOnCommitCallbacks(execute=True):
              PricePlanService.update_custom_price_plans(...)
          self.assertTaskCommitted("workers.rentalsunited.push_prices")
  ```
  `assertTaskDispatched(name, **kwargs)` / `dispatched_tasks` = enqueued;
  `assertTaskCommitted` / `assertTaskNotCommitted` = survives the transaction;
  `assertNoTasksDispatched()`, `get_dispatched(name)`. Run a task body with `task.run(...)`.
- Factories: reuse the app's factory module (`<app>/tests/factories.py` or
  `<app>/api/tests/factories.py`); `Trait`s for variants, `post_generation` for M2M, `_create`
  writing the provider link too (`SmartDeviceFactory`), `Sequence` for unique keys.
- `self.client.force_login(user)`. Mock external SDKs at the boundary; never hit a provider.
- Test services and adapters directly; test views for serialization, flow and permissions (403 per
  access level, 404 cross-company). A bug fix ships a test that fails without it.
- A validation test asserts the exact message, not only the 400; a message that never shows
  (§5) passes a status-only test.
- Names are behaviour sentences (`test_unmapped_property_returns_200_without_reservation_dispatch`);
  date-sensitive tests use property-timezone dates.

## 21. Integrations

### Client and request logging

- One wrapper per provider: `RentalsUnitedClient` (`runited/client.py`), `PriceLabClient`
  (`common/client.py`), Seam via `get_seam_client()`; workers use `get_ru_client()` /
  `get_pl_client()` (`workers/utils.py`). Synchronous paths pass an explicit timeout.
- Branch on the raw provider code (`get_ru_error_code(exc)`), never `str(exc)`. A response with no
  verdict is a failure.
- **Every webhook and outbound call is an `integrations.Log` row**: outbound from the client's
  response hook (`handle_ru_logging`, `handle_pl_logging`, `handle_seam_logging` in
  `common/utils.py`, set as `session.hooks["response"]`; Seam's SDK is patched in
  `SeamDevicesConfig.ready`); inbound as the webhook view's first statement
  (`status="Processing"`), updated with `status` and `logs["exc"]`. New integrations add a
  `Log.integration` code; never use a bare `requests` session.

| Field | Holds |
| --- | --- |
| `integration` | `RU`, `PL`, `SM`, `ST`, `FB` (`guess_integration_name(url)` outbound) |
| `direction` | `INCOMING` for webhooks, `OUTGOING` (default) for client calls |
| `request_id` | outbound: URL or RU response type; inbound: event type / provider event id |
| `logs` | JSON `request`, `response`, `exc`; inbound: raw payload (`headers` where auth needs them) |
| `status` | HTTP/provider status or a word (`Processing`, `Success`, `Failed`, `received`) |

- `Log` is audit only; idempotency is a unique event row (`StripeConnectEvent.event_id`) or the link
  row. Tasks are recorded by `CustomTask` as `workers.Job` rows. User-actionable problems are
  `IntegrationWarning`s.

### Adapters

- **Inbound** (`adapters/inbound.py`): pydantic with `Field(alias=...)` / `AliasPath(...)`;
  `to_service_data()` feeds the service, which writes.
- **Tolerant** (`adapters/tolerant.py`): subclass `TolerantImportModel`, record problems on an
  `ImportWarningCollector`, end the class with `_collect_warnings = collect_warnings()`.
- **Outbound** (`adapters/outbound.py`): `PydanticDjangoModel` via `model_validate(instance)` with
  `@computed_field` provider fields; simpler providers use a `payload` property or functions.
- Quirk helpers once (`_node`, `_as_list`); per-channel rules as data (`CHANNEL_FAMILY_REPUSH_CONFIG`),
  never branching on a channel name. Provider identity is copied verbatim to the link row; OTA free
  text goes to `external_data`. Warnings sync via `IntegrationWarningService(instance, source,
  category).sync([...])`, `sync([])` on a clean run.

### Webhooks

- One authentication class per provider as the view's **only** one: HMAC
  (`SeamWebhookAuthentication`, `PriceLabAuthentication`, `StripeWebhookAuthentication`), body
  credentials (`RentalsUnitedRLNMAuthentication`), or a secret URL segment via
  `constant_time_compare`, failing closed. Adding session auth breaks provider POSTs.
- Raw-body signatures need a parser that keeps it (`PriceLabJSONParser`); XML uses
  `common.api.parsers.XMLParser` + `XMLRenderer`.
- Log, validate, then dispatch via `EventRouter` or a task (`countdown` for events the provider is
  still processing); no inline provider calls. Apply synchronously only cheap, event-id-deduplicated
  writes.
- Return **200** for failures a retry can't fix, recorded on the `Log`. Resolve by link-row provider
  id, discard echoes of our pushes (`claim_host_message_echo`), defer events that beat their parent.

### Stripe

- All calls go through `integrations/stripe/services/` (`StripePaymentIntentService`,
  `StripeRefundService`, `StripeCustomerService`, …); key and timeout are set in `StripeConfig.ready`.
- Direct-booking money moves on the connected account: pass `stripe_account` on every call.
- Mutating calls take `idempotency_key=f"<op>:<id>:<token>"`. Look up an existing result first, use
  a fresh key per attempt, and re-check Stripe after `APIConnectionError` before reporting failure.
- Map `stripe.StripeError` codes to a 409 with our message. Endpoints are registered with
  `setup_stripe_webhook`; each has its own signing secret (`secret_setting` on the auth class).

### Mapping dictionaries

- Provider lookup lists mirror into `Dictionary` rows from one registry (`RU_DICTIONARIES`),
  insert-only. Our → provider mappings are `DictionaryMapping` rows seeded from one module
  (`amenity_mappings.py`, `fee_mappings.py`) with a test that every object is mapped or listed as
  unmapped.

### Testing integrations

- Patch the client where the worker gets it (`patch("workers.rentalsunited.get_ru_client")`,
  `patch.object(SmartDeviceService, "client")`) or use `SeamMockMixin`.
- Feed adapters captured payloads through the production parser (`XMLParser().parse(xml.encode())`).
- Webhook tests post to the real URL with real auth inputs and assert the `Log` row and tasks.

## 22. Recipes

**New endpoint.** Model + choices + constraints → migration. Service (export from
`services/__init__.py`) and selector. Serializer. Viewset: `GenericViewSet` + needed mixins,
company-scoped `get_queryset`, `EnforcePermissionsMixin` with a codename per method/action,
`perform_create`/action making one service call. Register in `api/urls.py`. Tests: service test +
view test (permissions, 404 cross-company), module in `TEST_SUITE`.

**New model + migration.** `BaseModel`, `property_object`/`company` FK, constraints in
`Meta(BaseModel.Meta)`, `__str__`, admin registration with `readonly_fields` for system fields.
One `makemigrations <app>`; seeds as a separate data migration in the same change.

**New side effect / task.** Task in `workers/<area>.py` (`@shared_task(bind=True)`, ids,
`**kwargs`, no return). Add or extend the `EventRegistry.mappings` entry; dispatch from the service
via `EventRouter`. Test with `CaptureTasksMixin` (`assertTaskCommitted` when inside `atomic`).

**New integration webhook.** Authentication class in `api/authentication.py`; view with only that
class; `Log` row first; inbound adapter → service or task; 200 for unretryable failures; URL under
the integration's `api/urls.py`. Test through the URL with signed inputs.

**New integration.** Mirror `integrations/seamdevices`: link models, `choices.py`, `client.py` with
a logging hook and `Log.integration` code, `adapters/`, `services.py`, `authentication.py`, `api/`,
tasks in `workers/<name>.py`, a mock mixin in `tests/`, a `CLAUDE.md` for its invariants.

## 23. Design patterns

| Pattern | Where | Use when |
| --- | --- | --- |
| Adapter | `runited/adapters/`, `pricelabs/adapters/outbound.py`, `seamdevices/adapters.py` | translating provider shape ⇄ ours |
| Gateway (client wrapper) | `runited/client.py`, `common/client.py`, `stripe/services/` | any outbound provider call |
| Service layer | `<app>/services.py` | every write / business rule |
| Selector / read model | `<app>/selectors.py`, `runited.selectors.PropertySelector` | reads and payload assembly |
| Observer (event bus) | `workers/event_router.py` | a change must trigger work elsewhere |
| Registry dispatch | `seamdevices/webhooks/registry.py`, `get_review_adapter` | one handler per event/channel type |
| Table-driven strategy | `CHANNEL_FAMILY_REPUSH_CONFIG`, `RU_DICTIONARIES` | behaviour varies by provider family |
| Template method | `CustomTask`, `BaseWebhookHandler`, `PriceLabBaseAPIView` | shared lifecycle, varying step |
| Mixin | `EnforcePermissionsMixin`, `CaptureTasksMixin`, `CSVExportMixin`, `SeamMockMixin` | one cross-cutting behaviour |
| Custom QuerySet manager | `PricePlanQuerySet` (`properties/models/plans.py`) | a rule every query/bulk write obeys |
| Decorator | `flags_failed_import` (`workers/services/rentalsunited.py`) | same failure handling around tasks |
| Collecting parameter | `ImportWarningCollector` | gather non-fatal problems across a run |
| Link model | `SeamDeviceLink`, `RUProperty`, `RUReservation` | attach provider identity to a domain row |
| Dedup lane | `enqueue_if_not_pending` | every task dispatch |
| Pipeline | `celery.chain(...)` in `push_complete_property` | ordered steps |

- **Adapter**: one-way; `payload → parser → Log → InboundAdapter → .to_service_data() → service`
  and `model → OutboundAdapter.model_validate(instance) → payload → client → Log`.
- **Gateway**: wraps transport, logging and error decoding; the raised exception carries the raw
  provider code (`exc.code`, read by `get_ru_error_code`).
- **Service layer / Selector**: one service call per entry point; reads return querysets or dicts.
- **Observer**: producers announce `model:event` with an actor; `EventRegistry` maps it to tasks;
  the router records an `Event`, merges duplicates and enqueues via the dedup lane. Add a consumer
  with a registry entry, not a call from the producer.
- **Registry dispatch**: handlers self-register (`@register("lock", "locked")`); unknown keys are
  ignored with a warning.
- **Table-driven strategy**: adding a provider family is a data change.
- **Template method**: the base owns the lifecycle (`CustomTask`: `Job`, dedup release,
  `TaskFailure`; `PriceLabBaseAPIView.post` logs/validates, subclasses override `perform_post`).
- **Mixin**: one behaviour, composed left of the base class.
- **Custom QuerySet manager**: guards bulk paths that bypass `save()`.
- **Decorator**: `@flags_failed_import` under `@shared_task(bind=True)`.
- **Collecting parameter**: one `ImportWarningCollector` per import, persisted once via
  `collector.as_payloads()` → `IntegrationWarningService.sync`.
- **Link model**: resolve through it (`Device.objects.filter(seam_link__seam_device_id=...)`).
- **Dedup lane**: a pending copy on the lane suppresses duplicates from any producer; the lock is
  released in `CustomTask.before_start`; `content_dedup=True` / `state_hash=` skip unchanged work.

## 24. Footguns

- `get_or_create` returns `(obj, created)`; use `update_or_create` when the row may exist with
  changed data. It already checks for the row: no `exists()` in front of it, and branches that
  differ only in defaults pass the difference in (`defaults={"<field>": not created}`).
- A message in `validate_<field>` for a check the field already makes (blank, `max_length`) never
  shows; DRF's default message wins.
- `DRF_NUM_PROXIES` defaults to 1. With two appending proxies (load balancer + nginx) every
  visitor resolves to the load balancer: one throttle bucket for the whole platform.
- `Availability` rows can be both `booked` and `blocked`; filter on the flag you mean.
- `update()` / `bulk_update` skip `save()` and signals and don't touch `updated_at` (`auto_now`);
  include it yourself.
- A task you expect to run but doesn't is usually held by its pending `dedup:{task}:{id}` lock or an
  unchanged `last_run` hash — check the lane, don't bypass `enqueue_if_not_pending`.
- A task enqueued inside `atomic()` runs only after commit; assert with `assertTaskCommitted`.
- Provider-local times (Seam access codes, RU dates) are not UTC; convert in the adapter.

## 25. Review checklist

- [ ] Root cause fixed in the shared path (no widened permission, no swallowed exception).
- [ ] All sibling paths covered: create/update/delete, every screen using the endpoint, plurality.
- [ ] Viewset makes one service call; no business rules in serializers, views or admin actions.
- [ ] Side effects via `EventRouter` / `enqueue_if_not_pending` / `on_commit` from the service,
      after its guards; a 400 leaves no `Event` row.
- [ ] Tasks in `workers/`, accept `**kwargs`, return nothing, guard every loop item (release
      tasks and commands too).
- [ ] Scheduled tasks load once per run; per-item queries multiplied by items × accounts ×
      frequency.
- [ ] No `SerializerMethodField` for a plain attribute path:
      `ReadOnlyField(source="pending_request.action", allow_null=True)`.
- [ ] Pending / in-flight flags written under `select_for_update` with a re-check, or a partial
      unique constraint.
- [ ] Querysets company-scoped, `is_deleted=False`; cross-company ids 404.
- [ ] Codename for every method/action; `permission_classes =` only where §4 allows; public
      endpoints throttled; no secrets returned.
- [ ] Invariants as DB constraints; idempotency as unique rows; races via `select_for_update` +
      `IntegrityError` handling.
- [ ] Choices in `choices.py`, provider enums fully covered; user messages are constants.
- [ ] No N+1; bulk ops batched; filtered columns indexed.
- [ ] Money in `Decimal`, quantized, cents only at the client; Stripe calls carry `stripe_account`
      and an idempotency key.
- [ ] No secrets or PII in code, logs or errors; raw SQL parameterized.
- [ ] Secrets in URLs carry their own `Referrer-Policy`; security settings overridden per
      surface, not globally; client IP via the throttle's `get_ident()` with `DRF_NUM_PROXIES`
      matching each environment's proxy chain.
- [ ] No wildcard `ALLOWED_HOSTS`; a host rewrite covers `X-Forwarded-Host` and `Origin`; public
      URLs from the original host. Login-free links signed, expiring, `noindex`, uncached, with
      forbidden actions refused on the server. Customer-written public content on
      `simplihost.com` raised as a decision.
- [ ] Field-level messages in `error_messages`; no strip-only `validate_<field>`; no model limits
      restated in `extra_kwargs`; tests assert the message.
- [ ] Validators in `<app>/validators.py`; constants under the imports; each served surface a
      sub-package; no `exists()` before `get_or_create`.
- [ ] Response fields only added; `@extend_schema` on custom actions.
- [ ] Provider data: every call/webhook in `Log`, mapped in adapters, written by one service; local
      state committed only after the provider accepted.
- [ ] App ownership (§3): provider-specific data on the integration's link model, host-facing
      facts on the domain model; no domain import of `integrations.*`; no domain field deleted
      because a provider stopped writing it.
- [ ] Webhooks: sole auth class, `Log` row first, 200 for unretryable failures, no inline calls.
- [ ] No derived fields or dead code; removed things removed everywhere; existing code reused.
- [ ] Admin: system fields `readonly_fields`, audit logs read-only, actions call services.
- [ ] One migration, renumbered on `main`; seeds frozen, idempotent, reversible.
- [ ] Tests in `TEST_SUITE`, using `PropertyBaseTestCase` + `CaptureTasksMixin`; providers mocked.
- [ ] CRLF files keep their line endings.
