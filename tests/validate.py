#!/usr/bin/env python3
"""Valida events.json / todos.json / status.json contra docs/CONTRACTS.md.

Uso:  python3 tests/validate.py <directorio-con-los-json>
Sale con 0 si todo cumple el contrato, 1 si no. Imprime cada incumplimiento.
"""
import json
import re
import sys
from pathlib import Path

ISO = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")

errors = []


def bad(where, msg):
    errors.append(f"{where}: {msg}")


def check(cond, where, msg):
    if not cond:
        bad(where, msg)


def field(obj, key, where, types, *, optional_null=False, pattern=None):
    if key not in obj:
        bad(where, f"falta el campo '{key}'")
        return None
    v = obj[key]
    if v is None:
        if not optional_null:
            bad(where, f"'{key}' no puede ser null")
        return None
    if not isinstance(v, types):
        bad(where, f"'{key}' tiene tipo {type(v).__name__}, se esperaba {types}")
        return v
    if pattern and isinstance(v, str) and not pattern.match(v):
        bad(where, f"'{key}' = {v!r} no cumple el formato esperado")
    return v


def validate_events(doc):
    check(doc.get("schema") == 1, "events", "schema debe ser 1")
    field(doc, "generated", "events", str, pattern=ISO)
    rng = field(doc, "range", "events", dict) or {}
    field(rng, "start", "events.range", str, pattern=DATE)
    field(rng, "end", "events.range", str, pattern=DATE)
    for i, c in enumerate(doc.get("calendars", [])):
        field(c, "name", f"events.calendars[{i}]", str)
        field(c, "color", f"events.calendars[{i}]", str, pattern=HEX)
    keys = set()
    prev = None
    for i, e in enumerate(doc.get("events", [])):
        w = f"events[{i}]"
        field(e, "uid", w, str)
        k = field(e, "key", w, str)
        if k is not None:
            check(k not in keys, w, f"'key' duplicada: {k}")
            keys.add(k)
        field(e, "title", w, str)
        field(e, "calendar", w, str)
        field(e, "color", w, str, pattern=HEX)
        all_day = field(e, "allDay", w, bool)
        start = field(e, "start", w, str, optional_null=True, pattern=ISO)
        end = field(e, "end", w, str, optional_null=True, pattern=ISO)
        sd = field(e, "startDate", w, str, pattern=DATE)
        ed = field(e, "endDate", w, str, pattern=DATE)
        dur = field(e, "durationMinutes", w, int, optional_null=True)
        if all_day is True:
            check(start is None and end is None, w, "allDay=true exige start y end null")
            check(dur is None, w, "allDay=true exige durationMinutes null")
        elif all_day is False:
            check(start is not None and end is not None, w, "allDay=false exige start y end")
            check(dur is not None, w, "allDay=false exige durationMinutes")
        if sd and ed:
            check(sd <= ed, w, f"startDate {sd} > endDate {ed}")
        for k2 in ("location", "description", "url"):
            field(e, k2, w, str, optional_null=True)
        field(e, "recurring", w, bool)
        field(e, "cancelled", w, bool)
        st = field(e, "status", w, str, optional_null=True)
        check(st in (None, "CONFIRMED", "TENTATIVE", "CANCELLED"), w, f"status inválido: {st}")
        field(e, "categories", w, list)
        order = (sd or "", 0 if all_day else 1, start or "", e.get("title") or "")
        if prev is not None:
            check(prev <= order, w, f"orden incorrecto: {order} va detrás de {prev}")
        prev = order


def validate_todos(doc):
    check(doc.get("schema") == 1, "todos", "schema debe ser 1")
    field(doc, "generated", "todos", str, pattern=ISO)
    list_names = set()
    for i, l in enumerate(doc.get("lists", [])):
        w = f"todos.lists[{i}]"
        n = field(l, "name", w, str)
        list_names.add(n)
        field(l, "color", w, str, pattern=HEX)
        field(l, "pending", w, int)
        field(l, "completed", w, int)
    uids = set()
    prev = None
    for i, t in enumerate(doc.get("todos", [])):
        w = f"todos[{i}]"
        u = field(t, "uid", w, str)
        if u is not None:
            check(u not in uids, w, f"uid duplicado: {u}")
            uids.add(u)
        field(t, "summary", w, str)
        ln = field(t, "list", w, str)
        check(ln in list_names, w, f"la lista '{ln}' no aparece en 'lists'")
        field(t, "color", w, str, pattern=HEX)
        done = field(t, "completed", w, bool)
        ca = field(t, "completedAt", w, str, optional_null=True, pattern=ISO)
        if done is False:
            check(ca is None, w, "completed=false exige completedAt null")
        due = field(t, "due", w, str, optional_null=True, pattern=ISO)
        dd = field(t, "dueDate", w, str, optional_null=True, pattern=DATE)
        check((due is None) == (dd is None), w, "due y dueDate deben ser ambos null o ambos no null")
        field(t, "dueAllDay", w, bool)
        overdue = field(t, "overdue", w, bool)
        if due is None:
            check(overdue is False, w, "sin due no puede estar overdue")
        p = field(t, "priority", w, int)
        check(p is None or 0 <= p <= 9, w, f"priority fuera de 0..9: {p}")
        pl = field(t, "priorityLabel", w, str)
        expected = "none" if p == 0 else "high" if p and p <= 4 else "medium" if p == 5 else "low"
        check(pl == expected, w, f"priorityLabel '{pl}' no corresponde a priority {p} (se esperaba '{expected}')")
        pc = field(t, "percent", w, int)
        check(pc is None or 0 <= pc <= 100, w, f"percent fuera de 0..100: {pc}")
        field(t, "description", w, str, optional_null=True)
        field(t, "categories", w, list)
        field(t, "created", w, str, optional_null=True, pattern=ISO)
        order = (1 if done else 0, 0 if overdue else 1, due or "9999", 10 if p == 0 else (p or 10), t.get("summary") or "")
        if prev is not None:
            check(prev <= order, w, f"orden incorrecto: {order} va detrás de {prev}")
        prev = order


def validate_status(doc):
    check(doc.get("schema") == 1, "status", "schema debe ser 1")
    st = field(doc, "state", "status", str)
    check(st in ("ok", "syncing", "stale", "error"), "status", f"state inválido: {st}")
    field(doc, "lastSync", "status", str, optional_null=True, pattern=ISO)
    field(doc, "lastSyncOk", "status", str, optional_null=True, pattern=ISO)
    field(doc, "durationMs", "status", int)
    err = field(doc, "error", "status", str, optional_null=True)
    kind = field(doc, "errorKind", "status", str, optional_null=True)
    check(kind in (None, "network", "auth", "server", "config", "tool", "unknown"),
          "status", f"errorKind inválido: {kind}")
    if st in ("error", "stale"):
        check(err is not None and kind is not None, "status", f"state '{st}' exige error y errorKind")
    if st == "ok":
        check(err is None and kind is None, "status", "state 'ok' exige error y errorKind null")
    counts = field(doc, "counts", "status", dict) or {}
    for k in ("events", "todos", "calendars", "lists"):
        field(counts, k, "status.counts", int)


VALIDATORS = {"events": validate_events, "todos": validate_todos, "status": validate_status}


def main() -> int:
    base = Path(sys.argv[1] if len(sys.argv) > 1 else "tests/fixtures")
    checked = 0
    for path in sorted(base.glob("*.json")):
        kind = path.stem.split("-")[0]
        if kind not in VALIDATORS:
            continue
        try:
            doc = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            bad(path.name, f"JSON inválido: {exc}")
            continue
        before = len(errors)
        VALIDATORS[kind](doc)
        checked += 1
        status = "OK" if len(errors) == before else "FALLA"
        print(f"{status:5} {path}")
    if not checked:
        print(f"No se encontró ningún JSON del contrato en {base}", file=sys.stderr)
        return 1
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
