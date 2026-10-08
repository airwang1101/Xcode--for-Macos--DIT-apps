#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import shutil
import sys
import uuid
from pathlib import Path


MAC_ABSOLUTE_EPOCH = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)
DEFAULT_BUNDLE_ID = "com.airwang.ditformac.dev"
REPORT_FILE_NAME = "import-reports.json"
STATISTICS_INDEX_FILE_NAME = "statistics-index.json"


def swift_date(value: dt.datetime) -> float:
    return (value.astimezone(dt.timezone.utc) - MAC_ABSOLUTE_EPOCH).total_seconds()


def parse_anchor(value: str) -> dt.datetime:
    try:
        parsed = dt.datetime.strptime(value, "%Y-%m-%d")
    except ValueError as error:
        raise argparse.ArgumentTypeError("expected YYYY-MM-DD") from error
    return parsed.replace(hour=23, minute=0, second=0, tzinfo=dt.timezone.utc)


def default_data_dir(bundle_id: str) -> Path:
    return Path.home() / "Library" / "Application Support" / bundle_id / "Data"


def backup_file(path: Path, suffix: str) -> Path | None:
    if not path.exists():
        return None
    backup_path = path.with_name(f"{path.stem}.{suffix}{path.suffix}")
    shutil.copy2(path, backup_path)
    return backup_path


def make_report(index: int, anchor: dt.datetime, day_span: int) -> dict:
    source_names = ["A7M3 Card", "FX3 Card", "A7S3 Card", "Drone Card"]
    verification_modes = [
        "SHA-256 全量校验",
        "快速指纹校验",
        "大小校验",
    ]
    day = (anchor - dt.timedelta(days=index % day_span)).replace(hour=0, minute=0, second=0, microsecond=0)
    finished_at = day + dt.timedelta(seconds=index % 82800)
    source_name = source_names[index % len(source_names)]
    task_name = f"DIT_Stress_{index:05d}"
    success = index % 11 != 0
    cancelled = index % 97 == 0

    return {
        "id": str(uuid.UUID(int=index + 1)),
        "startedAt": swift_date(finished_at - dt.timedelta(seconds=60 + index % 600)),
        "finishedAt": swift_date(finished_at),
        "sourceName": source_name,
        "sourcePath": f"/Volumes/{source_name}",
        "sourceRootPath": f"/Volumes/{source_name}",
        "targetPath": f"/Volumes/Work/{task_name}",
        "backupPath": f"/Volumes/Backup/{task_name}" if index % 3 == 0 else None,
        "selectedFileCount": 1 + (index % 18),
        "totalBytes": 64000000 + (index % 240) * 8000000,
        "verificationMode": verification_modes[index % len(verification_modes)],
        "namingRule": "Stress",
        "success": success and not cancelled,
        "cancelled": cancelled,
        "failedFiles": [] if success else [f"clip_{index}.mov"],
        "copyFailedFiles": [],
        "verificationFailedFiles": [] if success else [f"clip_{index}.mov"],
        "skippedFiles": [],
        "verificationSummary": "ok" if success else "failed",
        "interruptionReason": "cancelled" if cancelled else None,
        "duration": 30 + index % 1200,
        "reportDocumentPath": None,
        "localReportDocumentPath": None,
        "reportDocumentWriteFailed": False,
        "importedItems": [],
        "fileRecords": [],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed large local statistics data for UI performance testing.")
    parser.add_argument("--count", type=int, default=10000, help="number of transfer reports to generate")
    parser.add_argument("--days", type=int, default=730, help="number of days to distribute reports across")
    parser.add_argument("--anchor", type=parse_anchor, default=parse_anchor(dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")))
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID, help="app bundle id used for Application Support")
    parser.add_argument("--data-dir", type=Path, help="override the Data directory")
    parser.add_argument("--no-backup", action="store_true", help="do not copy existing JSON files before writing")
    parser.add_argument("--dry-run", action="store_true", help="print target paths without writing files")
    args = parser.parse_args()

    if args.count < 0:
        parser.error("--count must be non-negative")
    if args.days <= 0:
        parser.error("--days must be greater than zero")

    data_dir = args.data_dir.expanduser() if args.data_dir else default_data_dir(args.bundle_id)
    reports_path = data_dir / REPORT_FILE_NAME
    statistics_index_path = data_dir / STATISTICS_INDEX_FILE_NAME
    reports = [make_report(index, args.anchor, args.days) for index in range(args.count)]
    payload = {
        "schemaVersion": 1,
        "reports": reports,
    }

    print(f"Data directory: {data_dir}")
    print(f"Report count: {args.count}")
    print(f"Report file: {reports_path}")
    print(f"Statistics index reset: {statistics_index_path}")
    if args.dry_run:
        return 0

    data_dir.mkdir(parents=True, exist_ok=True)
    timestamp = dt.datetime.now().strftime("stress-backup-%Y%m%d-%H%M%S")
    backups = []
    if not args.no_backup:
        for path in [reports_path, statistics_index_path]:
            backup_path = backup_file(path, timestamp)
            if backup_path:
                backups.append(backup_path)

    reports_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    if statistics_index_path.exists():
        statistics_index_path.unlink()

    for backup_path in backups:
        print(f"Backup: {backup_path}")
    print("Done. Relaunch the Debug app, then open the Statistics section.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
