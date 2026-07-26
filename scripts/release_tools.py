#!/usr/bin/env python3
"""Deterministic packaging and validation helpers for Metrilens releases."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import sys
import zipfile


SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
PROJECT_VERSION = re.compile(r"MARKETING_VERSION = ([^;]+);")
FIXED_ZIP_TIME = (2020, 1, 1, 0, 0, 0)
MAX_ARCHIVE_ENTRIES = 2_048
MAX_ARCHIVE_UNCOMPRESSED_BYTES = 10 * 1024 * 1024


class ReleaseValidationError(ValueError):
    pass


def validate_version(version: str) -> str:
    if not SEMVER.fullmatch(version):
        raise ReleaseValidationError(
            f"version must be semantic X.Y.Z without a leading v: {version!r}"
        )
    return version


def project_versions(project_text: str) -> set[str]:
    return {match.strip().strip('"') for match in PROJECT_VERSION.findall(project_text)}


def source_version(repo: Path) -> str:
    project = repo / "Metrilens.xcodeproj" / "project.pbxproj"
    versions = project_versions(project.read_text(encoding="utf-8"))
    if len(versions) != 1:
        raise ReleaseValidationError(
            f"project must contain one MARKETING_VERSION, found {sorted(versions)}"
        )
    return validate_version(next(iter(versions)))


def validate_source_version(repo: Path, version: str) -> None:
    validate_version(version)
    actual_version = source_version(repo)
    if actual_version != version:
        raise ReleaseValidationError(
            f"project MARKETING_VERSION is {actual_version}, expected {version}"
        )

    info = plistlib.loads((repo / "Metrilens" / "Info.plist").read_bytes())
    if info.get("CFBundleShortVersionString") != "$(MARKETING_VERSION)":
        raise ReleaseValidationError(
            "Info.plist must source CFBundleShortVersionString from MARKETING_VERSION"
        )


def bundle_metadata(app: Path) -> dict[str, str]:
    info_path = app / "Contents" / "Info.plist"
    executable = app / "Contents" / "MacOS" / "Metrilens"
    icon = app / "Contents" / "Resources" / "AppIcon.icns"
    if not info_path.is_file():
        raise ReleaseValidationError(f"missing bundle Info.plist: {info_path}")
    if not executable.is_file():
        raise ReleaseValidationError(f"missing bundle executable: {executable}")
    if not icon.is_file():
        raise ReleaseValidationError(f"missing compiled App icon: {icon}")

    info = plistlib.loads(info_path.read_bytes())
    return {
        "version": str(info.get("CFBundleShortVersionString", "")),
        "build": str(info.get("CFBundleVersion", "")),
        "executable": str(executable),
    }


def validate_bundle(app: Path, version: str, expected_arch: str = "arm64") -> None:
    validate_version(version)
    metadata = bundle_metadata(app)
    if metadata["version"] != version:
        raise ReleaseValidationError(
            f"bundle version is {metadata['version']!r}, expected {version!r}"
        )
    if not metadata["build"]:
        raise ReleaseValidationError("bundle build number is empty")

    result = subprocess.run(
        ["lipo", "-archs", metadata["executable"]],
        check=True,
        capture_output=True,
        text=True,
    )
    architectures = result.stdout.split()
    if architectures != [expected_arch]:
        raise ReleaseValidationError(
            f"bundle architectures are {architectures}, expected [{expected_arch!r}]"
        )


def _archive_entries(app: Path):
    root = app.parent
    yield app, app.relative_to(root)
    for path in sorted(app.rglob("*"), key=lambda item: item.as_posix()):
        yield path, path.relative_to(root)


def create_deterministic_archive(app: Path, output: Path) -> None:
    if not app.is_dir() or app.suffix != ".app":
        raise ReleaseValidationError(f"expected an .app directory: {app}")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    if temporary.exists():
        temporary.unlink()

    try:
        with zipfile.ZipFile(
            temporary,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=9,
        ) as archive:
            for path, relative in _archive_entries(app):
                name = relative.as_posix()
                is_directory = path.is_dir()
                if is_directory:
                    name += "/"
                info = zipfile.ZipInfo(name, FIXED_ZIP_TIME)
                mode = stat.S_IMODE(path.lstat().st_mode)
                info.create_system = 3
                info.external_attr = (mode | (stat.S_IFDIR if is_directory else stat.S_IFREG)) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, b"" if is_directory else path.read_bytes())
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()


def verify_archive(archive: Path, version: str) -> None:
    validate_version(version)
    if not archive.is_file():
        raise ReleaseValidationError(f"archive not found: {archive}")
    required = {
        "Metrilens.app/Contents/Info.plist",
        "Metrilens.app/Contents/MacOS/Metrilens",
        "Metrilens.app/Contents/Resources/AppIcon.icns",
    }
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        if len(entries) > MAX_ARCHIVE_ENTRIES:
            raise ReleaseValidationError(
                f"archive contains {len(entries)} entries, maximum is "
                f"{MAX_ARCHIVE_ENTRIES}"
            )
        names = {entry.filename for entry in entries}
        if len(names) != len(entries):
            raise ReleaseValidationError("archive contains duplicate entries")
        total_uncompressed = 0
        for entry in entries:
            name = entry.filename.rstrip("/")
            path = PurePosixPath(name)
            file_type = stat.S_IFMT(entry.external_attr >> 16)
            is_directory = entry.is_dir()
            if (
                not name
                or "\\" in name
                or path.is_absolute()
                or ".." in path.parts
                or path.parts[0] != "Metrilens.app"
                or bool(entry.flag_bits & 0x1)
                or (is_directory and file_type != stat.S_IFDIR)
                or (not is_directory and file_type != stat.S_IFREG)
            ):
                raise ReleaseValidationError(
                    f"archive contains unsafe entry: {entry.filename!r}"
                )
            total_uncompressed += entry.file_size
            if (
                entry.file_size > MAX_ARCHIVE_UNCOMPRESSED_BYTES
                or total_uncompressed > MAX_ARCHIVE_UNCOMPRESSED_BYTES
            ):
                raise ReleaseValidationError(
                    "archive exceeds the 10 MiB uncompressed size limit"
                )
        missing = required - names
        if missing:
            raise ReleaseValidationError(
                f"archive is missing required entries: {sorted(missing)}"
            )
        info = plistlib.loads(
            bundle.read("Metrilens.app/Contents/Info.plist")
        )
        if info.get("CFBundleShortVersionString") != version:
            raise ReleaseValidationError(
                "archive Info.plist version does not match the requested release"
            )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_checksum(archive: Path, output: Path) -> None:
    output.write_text(f"{sha256(archive)}  {archive.name}\n", encoding="utf-8")


def verify_checksum_file(archive: Path, checksum: Path) -> None:
    if not archive.is_file():
        raise ReleaseValidationError(f"archive not found: {archive}")
    if not checksum.is_file():
        raise ReleaseValidationError(f"checksum not found: {checksum}")
    lines = checksum.read_text(encoding="utf-8").splitlines()
    if len(lines) != 1:
        raise ReleaseValidationError("checksum file must contain exactly one line")
    match = re.fullmatch(r"([0-9a-fA-F]{64})  ([^/\\]+)", lines[0])
    if not match:
        raise ReleaseValidationError("checksum line must be '<sha256>  <filename>'")
    expected_digest, expected_name = match.groups()
    if expected_name != archive.name:
        raise ReleaseValidationError(
            f"checksum names {expected_name!r}, expected {archive.name!r}"
        )
    actual_digest = sha256(archive)
    if expected_digest.lower() != actual_digest:
        raise ReleaseValidationError(
            f"archive checksum is {actual_digest}, expected {expected_digest.lower()}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    source = subparsers.add_parser("check-source")
    source.add_argument("repo", type=Path)
    source.add_argument("version")

    source_value = subparsers.add_parser("source-version")
    source_value.add_argument("repo", type=Path)

    version_value = subparsers.add_parser("check-version")
    version_value.add_argument("version")

    bundle = subparsers.add_parser("check-bundle")
    bundle.add_argument("app", type=Path)
    bundle.add_argument("version")

    package = subparsers.add_parser("package")
    package.add_argument("app", type=Path)
    package.add_argument("version")
    package.add_argument("archive", type=Path)
    package.add_argument("checksum", type=Path)

    verify = subparsers.add_parser("verify-archive")
    verify.add_argument("archive", type=Path)
    verify.add_argument("version")

    checksum = subparsers.add_parser("verify-checksum")
    checksum.add_argument("archive", type=Path)
    checksum.add_argument("checksum", type=Path)

    args = parser.parse_args()
    try:
        if args.command == "check-source":
            validate_source_version(args.repo.resolve(), args.version)
        elif args.command == "source-version":
            print(source_version(args.repo.resolve()))
        elif args.command == "check-version":
            validate_version(args.version)
        elif args.command == "check-bundle":
            validate_bundle(args.app.resolve(), args.version)
        elif args.command == "package":
            validate_bundle(args.app.resolve(), args.version)
            create_deterministic_archive(args.app.resolve(), args.archive.resolve())
            verify_archive(args.archive.resolve(), args.version)
            write_checksum(args.archive.resolve(), args.checksum.resolve())
        elif args.command == "verify-archive":
            verify_archive(args.archive.resolve(), args.version)
        elif args.command == "verify-checksum":
            verify_checksum_file(
                args.archive.resolve(),
                args.checksum.resolve(),
            )
    except (
        OSError,
        UnicodeError,
        zipfile.BadZipFile,
        ReleaseValidationError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"release validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
