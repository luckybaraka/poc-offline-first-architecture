from rest_framework.response import Response
from rest_framework.views import APIView

from .engine import apply_op, changes_since
from .models import Record, SyncEvent

MAX_BATCH = 100


class HealthView(APIView):
    def get(self, request):
        return Response({"ok": True})


class PushView(APIView):
    """POST {"device_id": "...", "ops": [op, ...]} -> one result per op, in order."""

    def post(self, request):
        device_id = request.data.get("device_id", "unknown")
        ops = request.data.get("ops") or []
        if len(ops) > MAX_BATCH:
            return Response({"error": f"send at most {MAX_BATCH} ops per batch"}, status=413)

        results = [apply_op(op) for op in ops]
        count = lambda name: sum(1 for r in results if r["outcome"] == name)
        SyncEvent.objects.create(
            device_id=device_id, kind="push", ops_received=len(ops),
            ops_applied=count("applied") + count("merged") + count("conflict"),
            duplicates=count("duplicate"), merged=count("merged"), conflicts=count("conflict"),
        )
        return Response({"results": results})


class PullView(APIView):
    """GET ?since=<seq>&device_id=... -> field-level changes after that sequence number."""

    def get(self, request):
        try:
            since = int(request.query_params.get("since", 0))
        except ValueError:
            return Response({"error": "since must be a number"}, status=400)
        data = changes_since(since)
        SyncEvent.objects.create(device_id=request.query_params.get("device_id", "unknown"),
                                 kind="pull", changes_sent=len(data["changes"]))
        return Response(data)


class EventsView(APIView):
    """Server-side audit trail, newest first. Optional ?device_id= filter."""

    def get(self, request):
        qs = SyncEvent.objects.all()
        if request.query_params.get("device_id"):
            qs = qs.filter(device_id=request.query_params["device_id"])
        return Response([
            {"device_id": e.device_id, "kind": e.kind, "ops_received": e.ops_received,
             "ops_applied": e.ops_applied, "duplicates": e.duplicates, "merged": e.merged,
             "conflicts": e.conflicts, "changes_sent": e.changes_sent,
             "at": e.created_at.isoformat()}
            for e in qs[:100]
        ])


class RecordsView(APIView):
    """Read-only view of the server's copy, handy during the demo."""

    def get(self, request):
        return Response([
            {"id": str(r.id), "name": r.name, "phone": r.phone, "status": r.status,
             "deleted": r.deleted, "version": r.version, "updated_by": r.updated_by}
            for r in Record.objects.order_by("name")
        ])
