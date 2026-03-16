---
title: "Data Lifecycle"
subtitle: "Retention, rotation, and responsible deletion"
chapter: 12
section: "Security"
seo_title: "Data Lifecycle Management — Retention, Key Rotation, and Responsible Deletion for SaaS — 2026"
seo_description: "Data lifecycle management for SaaS: retention policies, key rotation procedures, audit log immutability, customer data deletion, and compliance-driven archival."
keywords: ["data retention", "key rotation", "data deletion", "GDPR", "audit logs", "credential rotation", "SaaS compliance"]
reading_time: "9 min"
difficulty: "advanced"
tech_stack: ["Next.js", "Supabase", "TypeScript"]
business_case: "Unmanaged data is a liability. Retention policies limit your blast radius. Rotation limits your exposure window. Responsible deletion earns customer trust and satisfies regulators."
---

# Data Lifecycle

> "Data you no longer need is not an asset. It is a liability with a breach attached."

## The Problem

Your application has been running for two years. The database contains:

- 18 months of webhook event logs that nobody queries
- API keys that were revoked a year ago but still sit in the table
- An encryption key that has never been rotated
- Customer data for accounts that were deleted six months ago, still fully intact
- Audit logs that grow by 50,000 rows per week with no archival plan

None of this is urgent. None of it is on fire. But all of it is risk.

Stale webhook logs are attack surface -- if the database is compromised, they reveal integration patterns and timing. Unrotated encryption keys mean a single compromise exposes every credential ever encrypted with that key. Retained customer data after deletion violates GDPR Article 17 and creates liability in every jurisdiction with right-to-erasure laws. Unbounded audit logs will eventually degrade database performance and complicate backups.

The underlying problem is that most teams think about data creation -- how to store it, how to query it, how to index it -- and never think about data retirement. Data has a lifecycle: it is created, it serves a purpose, that purpose expires, and then it must be archived or destroyed.

## The Principle

Every piece of data in your system must answer three questions:

**How long do we keep it?** This is your retention policy. Some data has legal retention requirements (financial records: 7 years). Some data has operational value that expires (webhook events: 90 days). Some data belongs to the customer and must be deletable on request.

**How do we protect it while we have it?** This is your rotation and encryption policy. Credentials and keys have a shelf life. The longer a key exists, the higher the probability it has been compromised. Rotation limits the exposure window.

**How do we destroy it when it is time?** This is your deletion policy. Deletion must be complete (no orphaned records), verified (confirmed across all tables and storage), and auditable (a record that deletion occurred, even though the data itself is gone).

## The Pattern

### Retention Periods

Define explicit retention periods for every data category in your system:

| Data Type | Retention Period | Justification | Storage |
|-----------|-----------------|---------------|---------|
| **Audit Logs** | 1 year minimum | Compliance (SOC 2 CC7.2, CC7.3) | Immutable database table |
| **Webhook Events** | 90 days | Debugging and idempotency | Database table |
| **Financial Records** | 7 years | Financial compliance | Database table |
| **Customer Data** | Until deleted by customer | Business data, GDPR right to erasure | Database tables |
| **Session Data** | 30 days | Auth provider managed | Provider infrastructure |
| **API Key Metadata** | Indefinite (revoked keys retained) | Audit trail | Database table |
| **Media/Recordings** | Per customer policy | Customer-controlled | Object storage |

The retention period is not a suggestion. It is a contract with your customers and regulators.

### Audit Log Immutability

Audit logs are the foundation of your compliance story. They must be immutable -- no updates, no deletes, no exceptions.

Enforce immutability at the database level:

```sql
-- Audit logs: INSERT only, no UPDATE or DELETE for regular users
ALTER TABLE "public"."audit_logs" ENABLE ROW LEVEL SECURITY;

-- Regular users can only INSERT
CREATE POLICY "audit_logs_insert_only"
  ON "public"."audit_logs"
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- No SELECT, UPDATE, or DELETE policy for regular users
-- Service role can read for reporting

-- Service role bypass for system reads
CREATE POLICY "audit_logs_service_role"
  ON "public"."audit_logs"
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
```

Each audit log entry captures the full context of the action:

```typescript
interface AuditLogEntry {
  id: string;
  action: string;              // "order.created", "user.deleted"
  entity_type: string;         // "order", "user", "api_key"
  entity_id: string;           // The affected record
  actor_id: string;            // Who performed the action
  organization_id: string;     // Tenant scope
  ip_address: string | null;   // Where it came from
  changes: Record<string, {    // Field-level diffs
    old: unknown;
    new: unknown;
  }>;
  metadata: Record<string, unknown>; // Additional context
  created_at: string;          // When it happened
}
```

**What gets logged:**
- Entity lifecycle events (create, update, delete)
- State transitions (status changes, role assignments)
- Credential lifecycle (API key create, revoke, delete)
- Payment events (succeeded, failed, refunded)
- Communication events (email sent, notification triggered)
- System events (webhook processed, scheduled job executed)

### Credential Rotation

Every credential in your system has a rotation schedule. Some rotate automatically (auth provider signing keys). Others require manual procedures.

| Credential | Rotation Frequency | Procedure |
|------------|-------------------|-----------|
| **API Keys (Customer)** | Yearly or on compromise | Customer revokes old key, creates new key |
| **Encryption Key** | Yearly or on compromise | Re-encrypt all data (see procedure below) |
| **Auth Signing Keys** | Managed by provider | Automatic via provider dashboard |
| **Database Service Key** | On compromise only | Rotate via database dashboard, update env vars |
| **Payment API Keys** | Yearly or on compromise | Rotate via provider dashboard, update env vars |
| **Webhook Secrets** | On compromise only | Rotate via provider dashboard, update env vars |

### Encryption Key Rotation Procedure

The encryption key protects all integration credentials stored in the database. Rotating it is a breaking change that requires re-encrypting every protected value.

```typescript
// scripts/rotate-encryption-key.ts
import { createServiceRoleClient } from "@/lib/supabase/server";
import { decrypt, encrypt } from "@/lib/encryption/credentials";

async function rotateEncryptionKey(oldKey: string, newKey: string) {
  const supabase = await createServiceRoleClient();

  // 1. Fetch all encrypted records
  const { data: credentials } = await supabase
    .from("integration_credentials")
    .select("id, encrypted_value");

  if (!credentials?.length) {
    console.log("No credentials to rotate");
    return;
  }

  // 2. Decrypt with old key, re-encrypt with new key
  for (const credential of credentials) {
    const plaintext = decrypt(credential.encrypted_value, oldKey);
    const reEncrypted = encrypt(plaintext, newKey);

    await supabase
      .from("integration_credentials")
      .update({ encrypted_value: reEncrypted })
      .eq("id", credential.id);
  }

  console.log(`Rotated ${credentials.length} credentials`);

  // 3. Update environment variable to new key
  // (Manual step: update INTEGRATION_ENCRYPTION_KEY in deployment platform)
}
```

**Critical:** This procedure must run during a maintenance window. After the script completes, the old key is useless and the new key is the only valid decryption key.

### API Key Lifecycle

API keys follow a strict lifecycle: creation, active use, optional expiry, revocation, and retention for audit.

**Creation:**
1. Admin creates a key in the application
2. The plaintext key is displayed exactly once
3. A SHA-256 hash is stored in the database (plaintext is never stored)
4. An audit log entry records the creation

**Authentication:**
```typescript
// On every API request
async function authenticateApiKey(keyHeader: string) {
  const keyHash = sha256(keyHeader);

  const { data: key } = await supabase
    .from("api_keys")
    .select("*")
    .eq("key_hash", keyHash)
    .is("revoked_at", null)
    .single();

  if (!key) return null;

  // Check expiry
  if (key.expires_at && new Date(key.expires_at) < new Date()) {
    return null;
  }

  return key;
}
```

**Revocation:**
1. Admin revokes the key in the application
2. `revoked_at` timestamp is set (soft delete)
3. The key is immediately rejected by auth middleware
4. An audit log entry records the revocation
5. The key record is retained indefinitely for audit trail

### Customer Data Deletion

When a customer requests data deletion, we follow a five-step process:

```
1. SOFT DELETE     — Set deleted_at timestamp on customer records
2. AUDIT ANONYMIZE — Retain audit logs, anonymize PII fields
3. CASCADE         — Remove associated records (orders, preferences, etc.)
4. CONFIRM         — Verify deletion across all tables and storage
5. PURGE           — Remove soft-deleted records after 30-day grace period
```

```typescript
// services/data-deletion.ts
async function deleteCustomerData(
  customerId: string,
  reason: string
): Promise<DeletionReport> {
  const supabase = await createServiceRoleClient();

  // 1. Soft delete the customer
  await supabase
    .from("customers")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", customerId);

  // 2. Anonymize PII in audit logs
  await supabase.rpc("anonymize_audit_logs_for_entity", {
    p_entity_type: "customer",
    p_entity_id: customerId,
  });

  // 3. Delete associated data
  await supabase.from("orders").delete().eq("customer_id", customerId);
  await supabase.from("preferences").delete().eq("customer_id", customerId);

  // 4. Remove from object storage
  await supabase.storage
    .from("customer-files")
    .remove([`${customerId}/*`]);

  // 5. Log the deletion event
  await logAuditEvent({
    action: "customer.data_deleted",
    entity_type: "customer",
    entity_id: customerId,
    metadata: { reason, deleted_tables: ["orders", "preferences"] },
  });

  return { customerId, status: "deleted", tables_affected: 3 };
}
```

The audit log records that deletion occurred, without retaining the deleted data. This satisfies both the right to erasure and the requirement for an audit trail.

### Archival Strategy

Data that exceeds its active retention period but must be preserved for compliance moves to cold storage:

```
1. EXPORT     — Periodically export old records to object storage (S3/GCS)
2. ARCHIVE    — Move records to a compressed, encrypted archive
3. PURGE      — Delete from the active database after confirmed archive
4. VERIFY     — Confirm archived data is accessible for compliance queries
```

```typescript
// scripts/archive-old-audit-logs.ts
async function archiveAuditLogs(olderThanDays: number) {
  const supabase = await createServiceRoleClient();
  const cutoff = new Date(Date.now() - olderThanDays * 86400000).toISOString();

  // 1. Export to object storage
  const { data: oldLogs } = await supabase
    .from("audit_logs")
    .select("*")
    .lt("created_at", cutoff);

  if (!oldLogs?.length) return;

  const archiveKey = `archives/audit-logs/${cutoff.slice(0, 10)}.json.gz`;
  await uploadCompressed(archiveKey, oldLogs);

  // 2. Verify archive is readable
  const verification = await downloadAndVerify(archiveKey);
  if (verification.rowCount !== oldLogs.length) {
    throw new Error("Archive verification failed — aborting purge");
  }

  // 3. Purge from active database
  await supabase
    .from("audit_logs")
    .delete()
    .lt("created_at", cutoff);

  console.log(`Archived ${oldLogs.length} audit logs to ${archiveKey}`);
}
```

### AI and Third-Party Data Handling

When your application uses AI models or third-party services, additional data hygiene rules apply:

- AI agents process data in-memory only -- no training on customer data
- AI prompts may contain entity metadata for context -- review what is sent
- Error tracking captures input/output for debugging -- review scrubbing rules to ensure customer PII is redacted
- Third-party integrations receive only the minimum data required for their function

### Environment Variable Security

Secrets are managed through the deployment platform, encrypted at rest, and segregated by environment:

```bash
# Production, staging, and development use separate credentials
# Never share secrets across environments

# Deployment platform stores:
INTEGRATION_ENCRYPTION_KEY=...     # Rotated yearly
STRIPE_SECRET_KEY=...              # Rotated yearly
WEBHOOK_SECRET=...                 # Rotated on compromise
DATABASE_SERVICE_ROLE_KEY=...      # Rotated on compromise
```

Pre-commit hooks prevent secrets from reaching version control:

```json
{
  "*.env*": [
    "echo 'ERROR: Environment files should not be committed!' && exit 1"
  ]
}
```

## The Business Case

**Reduced blast radius.** Retention policies limit how much data is exposed in a breach. If you retain 90 days of webhook logs instead of 3 years, a breach exposes 90 days of data. The difference in regulatory exposure, notification requirements, and customer impact is enormous.

**Compliance readiness.** GDPR requires the ability to delete customer data on request. SOC 2 requires audit log retention for at least one year. Financial regulators require seven-year retention of payment records. A defined data lifecycle maps directly to these requirements with evidence.

**Operational health.** Unbounded tables eventually cause performance problems: slower backups, larger indexes, more expensive queries. Archival keeps the active database lean and fast.

**Customer trust.** When a customer asks "What happens to my data if I leave?" and you can answer with a documented deletion procedure, verification steps, and a 30-day completion guarantee, they trust you with more data. Trust is the currency of SaaS.

**Reduced key compromise impact.** A key that has been rotated yearly has a maximum compromise window of 12 months. A key that has never been rotated has a compromise window equal to the lifetime of your application. Rotation does not prevent compromise -- it limits the damage.

The investment is a retention policy document, a rotation schedule, a deletion procedure, and an archival script. The return is measured in reduced regulatory risk, smaller breach impact, better performance, and the kind of operational maturity that enterprise customers require before signing a contract.

## Try It

```bash
npx modh-playbook init data-lifecycle
```
