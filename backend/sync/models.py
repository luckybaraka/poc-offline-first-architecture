"""Server-side storage for the offline-first PoC.

Record      - the current state of each record (the server's copy).
ChangeLog   - one row per field change, with a global sequence number.
              Clients pull "everything after seq N" (delta sync).
AppliedOp   - every operation ID the server has processed, with its result.
              A retried push gets the stored result back (idempotency).
SyncEvent   - audit trail of every push and pull, per device.
"""
import uuid

from django.db import models

STATUS_CHOICES = [
    ("ACTIVE", "Active"),
    ("INACTIVE", "Inactive"),
    ("SUSPENDED", "Suspended"),
]

# Fields a client is allowed to change through sync.
SYNCED_FIELDS = ("name", "phone", "status", "deleted")


class Record(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)  # generated on the device
    name = models.CharField(max_length=200, blank=True, default="")
    phone = models.CharField(max_length=50, blank=True, default="")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="ACTIVE")
    deleted = models.BooleanField(default=False)  # soft delete, so the delete can sync too
    version = models.PositiveIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)
    updated_by = models.CharField(max_length=100, blank=True, default="")

    def __str__(self):
        return f"{self.name} ({self.status}) v{self.version}"


class ChangeLog(models.Model):
    seq = models.BigAutoField(primary_key=True)
    record = models.ForeignKey(Record, on_delete=models.CASCADE, related_name="changes")
    field = models.CharField(max_length=50)
    value = models.JSONField()
    version = models.PositiveIntegerField()  # record version after this change
    device_id = models.CharField(max_length=100)
    client_ts = models.BigIntegerField()  # milliseconds, from the device clock
    op_id = models.UUIDField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["seq"]
        indexes = [models.Index(fields=["record", "version"])]


class AppliedOp(models.Model):
    op_id = models.UUIDField(primary_key=True)
    device_id = models.CharField(max_length=100)
    result = models.JSONField()
    applied_at = models.DateTimeField(auto_now_add=True)


class SyncEvent(models.Model):
    KIND_CHOICES = [("push", "Push"), ("pull", "Pull")]
    device_id = models.CharField(max_length=100)
    kind = models.CharField(max_length=10, choices=KIND_CHOICES)
    ops_received = models.PositiveIntegerField(default=0)
    ops_applied = models.PositiveIntegerField(default=0)
    duplicates = models.PositiveIntegerField(default=0)
    merged = models.PositiveIntegerField(default=0)
    conflicts = models.PositiveIntegerField(default=0)
    changes_sent = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
