import os
import threading

from kubefoundry.store.repository import Repository

_lock = threading.Lock()


def emit(job_id, event_type, payload):
    Repository().add_event(job_id, event_type, payload)


def append_log(job_id, log_dir, message, event_type="log.line", payload=None):
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
    line = message.rstrip("\n")
    with _lock:
        with open(os.path.join(log_dir, "job.log"), "a", encoding="utf-8", newline="\n") as fh:
            fh.write(line + "\n")
    data = payload or {}
    data["message"] = line
    emit(job_id, event_type, data)
