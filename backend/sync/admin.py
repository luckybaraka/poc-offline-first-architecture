from django.contrib import admin

from .models import AppliedOp, ChangeLog, Record, SyncEvent

admin.site.register(Record, list_display=("name", "phone", "status", "deleted", "version", "updated_by"))
admin.site.register(ChangeLog, list_display=("seq", "record", "field", "value", "version", "device_id"))
admin.site.register(AppliedOp, list_display=("op_id", "device_id", "applied_at"))
admin.site.register(SyncEvent, list_display=("created_at", "device_id", "kind", "ops_received",
                                             "duplicates", "merged", "conflicts", "changes_sent"))
