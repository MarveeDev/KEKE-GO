-- ============================================================================
-- KEKE — Migration M-09 (audit log)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-09), §8 (acceptance)
--                  KEKE_DATABASE_DESIGN.md §11 (audit_logs)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-00 only (independent of M-07/M-08/M-10; any time after M-00).
--
-- SCOPE (and ONLY this scope):
--   * public.audit_logs (append-only audit trail).
--   * idx_audit_entity, idx_audit_actor.
--
--   NOT in this migration (PROPOSED/OPEN — DB §11.1, manifest §5.2/§5.3):
--   * keke_audit_writer role, keke_audit role, audit.append_log() function.
--   * Any audit-related function/trigger/role/grant/revoke.
--   * No FK on actor_user_id (canonical design leaves it a bare UUID, "null for
--     system"). No ownership transfer (that is later privilege/enforcement work).
--
-- SCHEMA / OWNERSHIP / PRIVILEGES:
--   * Application table in `public`; NOT transferred to any role here.
--   * No GRANT/REVOKE issued here (the DB-enforced audit permission model is
--     OPEN and deferred). Append-only is realized by later not granting
--     UPDATE/DELETE to application roles.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- audit_logs — append-only audit trail for sensitive mutations and reads.
--   actor_user_id: NULL for system-initiated events (not FK'd — canonical).
--   before / after: sanitized pre/post snapshots.
-- ----------------------------------------------------------------------------
CREATE TABLE public.audit_logs (
    id            BIGSERIAL PRIMARY KEY,
    actor_user_id UUID,                       -- null for system
    actor_role    TEXT,
    action        TEXT NOT NULL,              -- 'ride.accept','driver.approve','payout.process', ...
    entity_type   TEXT NOT NULL,
    entity_id     TEXT NOT NULL,
    before        JSONB,                      -- pre-change snapshot (sanitized)
    after         JSONB,                      -- post-change snapshot (sanitized)
    ip_address    INET,
    correlation_id TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_entity ON public.audit_logs (entity_type, entity_id, created_at DESC);
CREATE INDEX idx_audit_actor  ON public.audit_logs (actor_user_id, created_at DESC);
