"""The sync engine: how pushed operations are applied, and how conflicts are settled.

An operation (op) is one local change made on a device:

    {
      "op_id":        "uuid",       # unique per change; makes retries safe
      "record_id":    "uuid",
      "type":         "create" | "update" | "delete",
      "fields":       {"status": "INACTIVE"},   # only the fields that changed (delta)
      "base_version": 3,            # the record version the device last saw
      "device_id":    "web-a",
      "client_ts":    1759750000000 # ms, device clock at the time of the change
    }

Conflict rules (field level):
  * No one else changed the record since base_version  -> apply.
  * Others changed it, but different fields              -> apply, outcome "merged".
  * Others changed the same field                        -> Last-Write-Wins on client_ts:
        newer edit  -> applied, field outcome "won"
        older edit  -> dropped, field outcome "lost" (device is told the kept value)
"""
from django.db import transaction

from .models import STATUS_CHOICES, SYNCED_FIELDS, AppliedOp, ChangeLog, Record

VALID_STATUSES = {code for code, _ in STATUS_CHOICES}


class OpError(ValueError):
    pass


def _validate(op):
    for key in ("op_id", "record_id", "type", "device_id", "client_ts"):
        if key not in op:
            raise OpError(f"missing '{key}'")
    if op["type"] not in ("create", "update", "delete"):
        raise OpError(f"unknown type '{op['type']}'")
    fields = dict(op.get("fields") or {})
    if op["type"] == "delete":
        fields = {"deleted": True}
    for name, value in fields.items():
        if name not in SYNCED_FIELDS:
            raise OpError(f"field '{name}' cannot be synced")
        if name == "status" and value not in VALID_STATUSES:
            raise OpError(f"invalid status '{value}'")
    if not fields:
        raise OpError("no fields to change")
    return fields


def _log(record, fields, op):
    for name, value in fields.items():
        ChangeLog.objects.create(
            record=record,
            field=name,
            value=value,
            version=record.version,
            device_id=op["device_id"],
            client_ts=op["client_ts"],
            op_id=op["op_id"],
        )


def apply_op(op):
    """Apply one operation. Safe to call twice with the same op_id."""
    try:
        fields = _validate(op)
    except OpError as exc:
        return {"op_id": op.get("op_id"), "record_id": op.get("record_id"),
                "outcome": "rejected", "error": str(exc)}

    with transaction.atomic():
        previous = AppliedOp.objects.filter(op_id=op["op_id"]).first()
        if previous:
            return {**previous.result, "outcome": "duplicate",
                    "original_outcome": previous.result["outcome"]}

        record = Record.objects.select_for_update().filter(pk=op["record_id"]).first()

        if record is None:
            if op["type"] != "create":
                result = {"op_id": op["op_id"], "record_id": op["record_id"],
                          "outcome": "rejected", "error": "unknown record"}
                AppliedOp.objects.create(op_id=op["op_id"], device_id=op["device_id"], result=result)
                return result
            record = Record(id=op["record_id"], version=1, updated_by=op["device_id"])
            for name, value in fields.items():
                setattr(record, name, value)
            record.save()
            _log(record, fields, op)
            result = {"op_id": op["op_id"], "record_id": str(record.id), "outcome": "applied",
                      "version": record.version,
                      "fields": {name: {"outcome": "applied"} for name in fields}}
            AppliedOp.objects.create(op_id=op["op_id"], device_id=op["device_id"], result=result)
            return result

        base_version = int(op.get("base_version") or 0)

        # Latest change per field made by OTHER devices since this device last synced.
        others = {}
        for change in (ChangeLog.objects.filter(record=record, version__gt=base_version)
                       .exclude(device_id=op["device_id"]).order_by("seq")):
            others[change.field] = change

        to_apply, field_results = {}, {}
        for name, value in fields.items():
            rival = others.get(name)
            if rival is None:
                to_apply[name] = value
                field_results[name] = {"outcome": "merged" if others else "applied"}
            elif op["client_ts"] > rival.client_ts:
                to_apply[name] = value
                field_results[name] = {"outcome": "won", "other_device": rival.device_id,
                                       "other_value": rival.value}
            else:
                field_results[name] = {"outcome": "lost", "other_device": rival.device_id,
                                       "server_value": getattr(record, name)}

        if to_apply:
            for name, value in to_apply.items():
                setattr(record, name, value)
            record.version += 1
            record.updated_by = op["device_id"]
            record.save()
            _log(record, to_apply, op)

        outcomes = {r["outcome"] for r in field_results.values()}
        if outcomes & {"won", "lost"}:
            outcome = "conflict"
        elif "merged" in outcomes:
            outcome = "merged"
        else:
            outcome = "applied"

        result = {"op_id": op["op_id"], "record_id": str(record.id), "outcome": outcome,
                  "version": record.version, "fields": field_results}
        AppliedOp.objects.create(op_id=op["op_id"], device_id=op["device_id"], result=result)
        return result


def changes_since(seq, limit=500):
    rows = list(ChangeLog.objects.filter(seq__gt=seq).order_by("seq")[: limit + 1])
    has_more = len(rows) > limit
    rows = rows[:limit]
    return {
        "changes": [
            {"seq": r.seq, "record_id": str(r.record_id), "field": r.field, "value": r.value,
             "version": r.version, "device_id": r.device_id, "client_ts": r.client_ts}
            for r in rows
        ],
        "next_seq": rows[-1].seq if rows else seq,
        "has_more": has_more,
    }
