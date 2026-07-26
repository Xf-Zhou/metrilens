import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest
import zipfile

import release_tools


class ReleaseToolsTests(unittest.TestCase):
    def test_version_validation_accepts_semver_and_rejects_tag_prefix(self):
        self.assertEqual(release_tools.validate_version("1.2.3"), "1.2.3")
        for invalid in ["v1.2.3", "1.2", "01.2.3", "1.2.3-beta"]:
            with self.subTest(invalid=invalid):
                with self.assertRaises(release_tools.ReleaseValidationError):
                    release_tools.validate_version(invalid)

    def test_project_version_parser_requires_one_consistent_value(self):
        text = """
            MARKETING_VERSION = 0.2.0;
            MARKETING_VERSION = "0.2.0";
        """
        self.assertEqual(release_tools.project_versions(text), {"0.2.0"})

    def test_source_version_rejects_mixed_project_values(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            project = repo / "Metrilens.xcodeproj"
            project.mkdir()
            (project / "project.pbxproj").write_text(
                "MARKETING_VERSION = 0.2.0;\n"
                "MARKETING_VERSION = 0.3.0;\n",
                encoding="utf-8",
            )
            with self.assertRaises(release_tools.ReleaseValidationError):
                release_tools.source_version(repo)

    def test_source_version_validation_covers_project_and_plist_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            project = repo / "Metrilens.xcodeproj"
            source = repo / "Metrilens"
            project.mkdir()
            source.mkdir()
            (project / "project.pbxproj").write_text(
                "MARKETING_VERSION = 0.2.0;\n"
                "MARKETING_VERSION = 0.2.0;\n",
                encoding="utf-8",
            )
            (source / "Info.plist").write_bytes(
                plistlib.dumps(
                    {"CFBundleShortVersionString": "$(MARKETING_VERSION)"}
                )
            )
            release_tools.validate_source_version(repo, "0.2.0")
            with self.assertRaises(release_tools.ReleaseValidationError):
                release_tools.validate_source_version(repo, "0.3.0")

    def test_archive_is_deterministic_and_has_expected_structure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "Metrilens.app"
            executable = app / "Contents" / "MacOS" / "Metrilens"
            resources = app / "Contents" / "Resources"
            executable.parent.mkdir(parents=True)
            resources.mkdir()
            executable.write_bytes(b"binary")
            executable.chmod(0o755)
            (resources / "AppIcon.icns").write_bytes(b"icon")
            (app / "Contents" / "Info.plist").write_bytes(
                plistlib.dumps(
                    {
                        "CFBundleShortVersionString": "0.2.0",
                        "CFBundleVersion": "1",
                    }
                )
            )
            first = root / "first.zip"
            second = root / "second.zip"
            release_tools.create_deterministic_archive(app, first)
            release_tools.create_deterministic_archive(app, second)

            self.assertEqual(release_tools.sha256(first), release_tools.sha256(second))
            release_tools.verify_archive(first, "0.2.0")
            with zipfile.ZipFile(first) as archive:
                self.assertIn(
                    "Metrilens.app/Contents/MacOS/Metrilens",
                    archive.namelist(),
                )

    def test_archive_validation_rejects_missing_icon(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive_path = Path(temporary) / "bad.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(
                    "Metrilens.app/Contents/Info.plist",
                    plistlib.dumps(
                        {
                            "CFBundleShortVersionString": "0.2.0",
                            "CFBundleVersion": "1",
                        }
                    ),
                )
                archive.writestr(
                    "Metrilens.app/Contents/MacOS/Metrilens",
                    b"binary",
                )
            with self.assertRaises(release_tools.ReleaseValidationError):
                release_tools.verify_archive(archive_path, "0.2.0")

    def test_release_workflow_uses_one_concurrency_key_for_push_and_dispatch(self):
        repository = Path(__file__).resolve().parent.parent
        release_driver = (
            repository / "scripts" / "release.sh"
        ).read_text(encoding="utf-8")
        workflow = (
            repository / ".github" / "workflows" / "release.yml"
        ).read_text(encoding="utf-8")

        self.assertIn('exec "$repo_dir/scripts/publish_release.sh"', release_driver)
        self.assertNotIn("gh release ", release_driver)
        self.assertIn("concurrency:", workflow)
        self.assertIn("group: release-${{ inputs.tag || github.ref_name }}", workflow)
        self.assertIn(
            './scripts/release.sh "$version" --publish-from-actions',
            workflow,
        )
        self.assertNotIn(
            './scripts/release.sh "$version" --publish\n',
            workflow,
        )

    def test_local_new_tag_only_pushes_and_never_writes_release(self):
        commands = self.run_publish_flow(
            mode="--publish",
            remote_tag=False,
            local_tag=False,
            release_state="missing",
        )

        self.assertIn("git tag -a v0.2.0", commands)
        self.assertIn("git push origin v0.2.0", commands)
        self.assert_no_release_writes(commands)

    def test_local_incomplete_release_only_dispatches_workflow(self):
        for state in ["missing", "draft"]:
            with self.subTest(state=state):
                commands = self.run_publish_flow(
                    mode="--publish",
                    remote_tag=True,
                    local_tag=True,
                    release_state=state,
                )

                self.assertIn(
                    "gh workflow run release.yml --ref v0.2.0 -f tag=v0.2.0",
                    commands,
                )
                self.assertNotIn("git push ", commands)
                self.assert_no_release_writes(commands)

    def test_local_published_release_is_read_only(self):
        commands = self.run_publish_flow(
            mode="--publish",
            remote_tag=True,
            local_tag=True,
            release_state="published",
        )

        self.assertIn("gh release download v0.2.0", commands)
        self.assertNotIn("gh workflow run ", commands)
        self.assertNotIn("git push ", commands)
        self.assert_no_release_writes(commands)

    def test_actions_internal_mode_is_the_only_release_writer(self):
        commands = self.run_publish_flow(
            mode="--publish-from-actions",
            remote_tag=True,
            local_tag=True,
            release_state="missing",
            actions=True,
        )

        self.assertIn("gh release create v0.2.0", commands)
        self.assertIn("gh release upload v0.2.0", commands)
        self.assertIn("gh release edit v0.2.0 --draft=false", commands)
        self.assertNotIn("gh workflow run ", commands)
        self.assertNotIn("git push ", commands)

    def test_actions_internal_mode_rejects_local_invocation_before_build(self):
        repository = Path(__file__).resolve().parent.parent
        environment = os.environ.copy()
        for key in ["GITHUB_ACTIONS", "GITHUB_REF_NAME", "GITHUB_REF_TYPE"]:
            environment.pop(key, None)

        result = subprocess.run(
            [
                "zsh",
                str(repository / "scripts" / "release.sh"),
                "0.2.0",
                "--publish-from-actions",
            ],
            check=False,
            capture_output=True,
            cwd=repository,
            env=environment,
            text=True,
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            result.stderr.strip(),
            "--publish-from-actions must run in GitHub Actions from tag v0.2.0",
        )

    def run_publish_flow(
        self,
        *,
        mode,
        remote_tag,
        local_tag,
        release_state,
        actions=False,
    ):
        repository = Path(__file__).resolve().parent.parent
        helper = repository / "scripts" / "publish_release.sh"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / "repo"
            mock_bin = root / "bin"
            repo.mkdir()
            mock_bin.mkdir()
            archive = root / "Metrilens-v0.2.0-macos-arm64.zip"
            checksum = root / f"{archive.name}.sha256"
            archive.write_bytes(b"archive")
            checksum.write_text("checksum\n", encoding="utf-8")
            command_log = root / "commands.log"
            state_file = root / "release-state"
            state_file.write_text(release_state, encoding="utf-8")

            self.write_executable(
                mock_bin / "git",
                """
                #!/usr/bin/env python3
                import os
                import sys

                args = sys.argv[1:]
                with open(os.environ["MOCK_COMMAND_LOG"], "a", encoding="utf-8") as log:
                    log.write("git " + " ".join(args) + "\\n")

                if args[:2] == ["status", "--porcelain"]:
                    raise SystemExit(0)
                if args[:2] == ["rev-parse", "HEAD"]:
                    print("head-commit")
                    raise SystemExit(0)
                if args[:2] == ["ls-remote", "--tags"]:
                    if os.environ["MOCK_REMOTE_TAG"] == "true":
                        ref = args[-1]
                        print(f"head-commit\\t{ref}")
                    raise SystemExit(0)
                if args[:3] == ["rev-parse", "--verify", "--quiet"]:
                    raise SystemExit(
                        0 if os.environ["MOCK_LOCAL_TAG"] == "true" else 1
                    )
                if args[:2] == ["rev-list", "-n"]:
                    print("head-commit")
                    raise SystemExit(0)
                raise SystemExit(0)
                """,
            )
            self.write_executable(
                mock_bin / "gh",
                """
                #!/usr/bin/env python3
                import os
                from pathlib import Path
                import shutil
                import sys

                args = sys.argv[1:]
                with open(os.environ["MOCK_COMMAND_LOG"], "a", encoding="utf-8") as log:
                    log.write("gh " + " ".join(args) + "\\n")

                state_path = Path(os.environ["MOCK_RELEASE_STATE"])
                state = state_path.read_text(encoding="utf-8")
                if args[:2] == ["workflow", "run"]:
                    raise SystemExit(0)
                if args[:2] == ["release", "view"]:
                    if state == "missing":
                        raise SystemExit(1)
                    if "--json" in args:
                        field = args[args.index("--json") + 1]
                        if field == "tagName":
                            print("v0.2.0")
                        elif field == "isDraft":
                            print("false" if state == "published" else "true")
                    raise SystemExit(0)
                if args[:2] == ["release", "create"]:
                    state_path.write_text("draft", encoding="utf-8")
                    raise SystemExit(0)
                if args[:2] == ["release", "upload"]:
                    raise SystemExit(0)
                if args[:2] == ["release", "download"]:
                    target = Path(args[args.index("--dir") + 1])
                    target.mkdir(parents=True, exist_ok=True)
                    for source_name in ["MOCK_ARCHIVE", "MOCK_CHECKSUM"]:
                        source = Path(os.environ[source_name])
                        shutil.copyfile(source, target / source.name)
                    raise SystemExit(0)
                if args[:2] == ["release", "edit"]:
                    state_path.write_text("published", encoding="utf-8")
                    raise SystemExit(0)
                raise SystemExit(2)
                """,
            )

            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{mock_bin}:{environment['PATH']}",
                    "MOCK_ARCHIVE": str(archive),
                    "MOCK_CHECKSUM": str(checksum),
                    "MOCK_COMMAND_LOG": str(command_log),
                    "MOCK_LOCAL_TAG": str(local_tag).lower(),
                    "MOCK_RELEASE_STATE": str(state_file),
                    "MOCK_REMOTE_TAG": str(remote_tag).lower(),
                }
            )
            if actions:
                environment.update(
                    {
                        "GITHUB_ACTIONS": "true",
                        "GITHUB_REF_NAME": "v0.2.0",
                        "GITHUB_REF_TYPE": "tag",
                    }
                )
            result = subprocess.run(
                [
                    "zsh",
                    str(helper),
                    str(repo),
                    "0.2.0",
                    str(archive),
                    str(checksum),
                    mode,
                ],
                check=False,
                capture_output=True,
                env=environment,
                text=True,
            )
            self.assertEqual(
                result.returncode,
                0,
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
            )
            return command_log.read_text(encoding="utf-8")

    def write_executable(self, path, contents):
        path.write_text(
            textwrap.dedent(contents).lstrip(),
            encoding="utf-8",
        )
        path.chmod(0o755)

    def assert_no_release_writes(self, commands):
        for operation in [
            "gh release create",
            "gh release upload",
            "gh release edit",
        ]:
            self.assertNotIn(operation, commands)


if __name__ == "__main__":
    unittest.main()
