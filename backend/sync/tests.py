import uuid

from rest_framework.test import APITestCase

REC = str(uuid.uuid4())


def op(device, type_="update", fields=None, base=0, ts=1000, record=REC):
    return {"op_id": str(uuid.uuid4()), "record_id": record, "type": type_,
            "fields": fields or {}, "base_version": base, "device_id": device, "client_ts": ts}


class SyncTests(APITestCase):
    def push(self, device, *ops):
        res = self.client.post("/api/sync/push/", {"device_id": device, "ops": list(ops)}, format="json")
        self.assertEqual(res.status_code, 200)
        return res.json()["results"]

    def pull(self, since=0):
        return self.client.get(f"/api/sync/pull/?since={since}&device_id=t").json()

    def setUp(self):
        self.push("phone", op("phone", "create", {"name": "Amina", "phone": "0700", "status": "ACTIVE"}))

    def test_create_and_pull(self):
        data = self.pull()
        self.assertEqual({c["field"] for c in data["changes"]}, {"name", "phone", "status"})

    def test_clean_update(self):
        [r] = self.push("phone", op("phone", fields={"status": "INACTIVE"}, base=1))
        self.assertEqual((r["outcome"], r["version"]), ("applied", 2))

    def test_duplicate_is_ignored(self):
        same = op("phone", fields={"status": "INACTIVE"}, base=1)
        self.push("phone", same)
        [r] = self.push("phone", same)
        self.assertEqual(r["outcome"], "duplicate")
        self.assertEqual(len(self.pull(since=3)["changes"]), 1)  # applied only once

    def test_different_fields_merge(self):
        self.push("web", op("web", fields={"phone": "0711"}, base=1, ts=2000))
        [r] = self.push("phone", op("phone", fields={"status": "SUSPENDED"}, base=1, ts=1500))
        self.assertEqual(r["outcome"], "merged")

    def test_same_field_last_write_wins(self):
        self.push("web", op("web", fields={"status": "SUSPENDED"}, base=1, ts=2000))
        [r] = self.push("phone", op("phone", fields={"status": "INACTIVE"}, base=1, ts=1500))
        self.assertEqual(r["fields"]["status"]["outcome"], "lost")
        self.assertEqual(r["fields"]["status"]["server_value"], "SUSPENDED")
        [r] = self.push("phone", op("phone", fields={"status": "INACTIVE"}, base=1, ts=3000))
        self.assertEqual(r["fields"]["status"]["outcome"], "won")

    def test_own_queued_edits_do_not_conflict(self):
        self.push("phone", op("phone", fields={"status": "INACTIVE"}, base=1, ts=1100))
        [r] = self.push("phone", op("phone", fields={"status": "SUSPENDED"}, base=1, ts=1200))
        self.assertEqual(r["outcome"], "applied")

    def test_invalid_status_rejected(self):
        [r] = self.push("phone", op("phone", fields={"status": "BOGUS"}, base=1))
        self.assertEqual(r["outcome"], "rejected")
