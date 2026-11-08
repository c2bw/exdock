import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import tarfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("publish_release", ROOT / "scripts/publish_release.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublicationGuardsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.revision = "a" * 40
        self.metadata = {
            "schema_version": 1, "version": "0.1.1", "tag": "v0.1.1",
            "repository": "example/exdock", "source": "https://github.com/example/exdock",
            "revision": self.revision, "image_revision": self.revision, "dirty": False,
            "platform": "linux/amd64", "packages": {"server": "0.1.1", "agent": "0.1.1"},
            "image_tags": {kind: "ghcr.io/example/exdock" + ("_client" if kind == "agent" else "") + ":v0.1.1" for kind in ("server", "agent")},
        }
        self.environment = {"GITHUB_REF": "refs/tags/v0.1.1", "GITHUB_SHA": self.revision,
                            "GITHUB_REPOSITORY": "example/exdock"}
        self.images = {}
        self.inspected = {}
        for kind, identity in (("server", "b"), ("agent", "c")):
            tag = "suite-" + kind + ":local"
            image_id = "sha256:" + identity * 64
            self.images[kind] = {"local_tag": tag, "id": image_id}
            self.inspected[tag] = {"Id": image_id, "Os": "linux", "Architecture": "amd64", "Config": {"Labels": {
                "org.opencontainers.image.version": "0.1.1", "org.opencontainers.image.revision": self.revision,
                "org.opencontainers.image.source": self.metadata["source"], "org.opencontainers.image.licenses": "MIT",
                "org.opencontainers.image.title": "Exdock " + kind}}}
        self.write()

    def write(self):
        (self.directory / "release.json").write_text(json.dumps(self.metadata))
        (self.directory / "images.json").write_text(json.dumps(self.images))
        (self.directory / "release-notes.md").write_text("Release notes\n")

    def validate(self):
        return publisher.validate(self.directory, self.inspected.__getitem__)

    def test_accepts_the_exported_pair_and_rejects_a_rebuilt_image(self):
        self.validate()
        self.inspected["suite-agent:local"]["Id"] = "sha256:" + "d" * 64
        with self.assertRaisesRegex(ValueError, "identity"):
            self.validate()

    def write_archive(self, path, configs):
        manifest = []
        with tarfile.open(path, "w") as archive:
            for tag, config in configs.items():
                identity = hashlib.sha256(config).hexdigest()
                name = "blobs/sha256/" + identity
                member = tarfile.TarInfo(name)
                member.size = len(config)
                archive.addfile(member, io.BytesIO(config))
                manifest.append({"Config": name, "RepoTags": [tag], "Layers": []})
            data = json.dumps(manifest).encode()
            member = tarfile.TarInfo("manifest.json")
            member.size = len(data)
            archive.addfile(member, io.BytesIO(data))

    def test_records_config_digests_and_preserves_native_test_ids(self):
        configs = {image["local_tag"]: json.dumps({"rootfs": {"diff_ids": [kind]}}).encode()
                   for kind, image in self.images.items()}
        self.write_archive(self.directory / "images.tar", configs)
        publisher.record_image_ids(self.directory)
        recorded = json.loads((self.directory / "images.json").read_text())
        for kind, image in recorded.items():
            self.assertEqual(image["source_image_id"], self.images[kind]["id"])
            self.assertEqual(image["id"], "sha256:" + hashlib.sha256(configs[image["local_tag"]]).hexdigest())

    def test_loaded_image_identity_is_independent_of_native_store_id(self):
        tag = "suite-server:local"
        config = b'{"rootfs":{"diff_ids":["sha256:layer"]}}'
        expected = "sha256:" + hashlib.sha256(config).hexdigest()
        for native_id in ("sha256:index-digest", expected):
            def run(*args, **kwargs):
                if args[:3] == ("docker", "image", "inspect"):
                    return json.dumps([self.inspected[tag] | {"Id": native_id}])
                self.assertEqual(args[:3], ("docker", "image", "save"))
                self.write_archive(Path(args[4]), {tag: config})
            with patch.object(publisher, "run", side_effect=run):
                self.assertEqual(publisher.inspect_image(tag)["Id"], expected)

    def test_changed_rootfs_is_rejected_even_with_matching_labels(self):
        tag = "suite-agent:local"
        tested_config = b'{"rootfs":{"diff_ids":["sha256:tested-layer"]}}'
        changed_config = b'{"rootfs":{"diff_ids":["sha256:different-layer"]}}'
        self.images["agent"]["id"] = "sha256:" + hashlib.sha256(tested_config).hexdigest()
        self.inspected[tag]["Id"] = "sha256:" + hashlib.sha256(changed_config).hexdigest()
        self.write()
        with self.assertRaisesRegex(ValueError, "identity"):
            self.validate()

    def test_rejects_wrong_revision_platform_source_and_version(self):
        original = copy.deepcopy(self.inspected)
        for field, value in (("revision", "d" * 40), ("version", "9.9.9"), ("source", "https://other.example")):
            self.inspected = copy.deepcopy(original)
            self.inspected["suite-server:local"]["Config"]["Labels"]["org.opencontainers.image." + field] = value
            with self.assertRaisesRegex(ValueError, "labels"):
                self.validate()
        self.inspected = original
        self.inspected["suite-agent:local"]["Architecture"] = "arm64"
        with self.assertRaisesRegex(ValueError, "platform"):
            self.validate()

    def test_requires_clean_matching_tag_commit_and_repository(self):
        publisher.require_publish_context(self.metadata, self.environment)
        for field, value in (("GITHUB_REF", "refs/heads/main"), ("GITHUB_SHA", "d" * 40),
                             ("GITHUB_REPOSITORY", "other/repository")):
            with self.assertRaises(ValueError):
                publisher.require_publish_context(self.metadata, self.environment | {field: value})
        self.metadata["dirty"] = True
        with self.assertRaisesRegex(ValueError, "dirty"):
            publisher.require_publish_context(self.metadata, self.environment)

    def test_rejects_prerelease_and_dirty_publication_before_docker_load(self):
        self.metadata["version"] = "0.2.0-rc.1"
        self.write()
        with self.assertRaisesRegex(ValueError, "version"):
            self.validate()
        self.metadata["version"] = "0.1.1"
        self.metadata["dirty"] = True
        self.write()
        with patch.dict(publisher.os.environ, self.environment), \
             patch("sys.argv", ["publish_release.py", str(self.directory)]), \
             patch.object(publisher, "run") as commands:
            with self.assertRaisesRegex(ValueError, "dirty"):
                publisher.main()
            commands.assert_not_called()

    def test_refuses_an_existing_release_before_pushing(self):
        existing = type("Response", (), {"returncode": 0, "stderr": ""})()
        with patch.dict(publisher.os.environ, self.environment), patch.object(publisher.subprocess, "run", return_value=existing), \
             patch.object(publisher, "run") as commands:
            with self.assertRaisesRegex(ValueError, "already exists"):
                publisher.publish(self.directory, self.metadata, self.images)
            commands.assert_not_called()

    def test_failed_second_push_never_creates_a_github_release(self):
        missing = type("Response", (), {"returncode": 1, "stderr": "HTTP 404"})()
        commands = []
        def run(*args, **kwargs):
            commands.append(args)
            if args[:2] == ("docker", "push") and "_client:" in args[2]:
                raise RuntimeError("Push failed")
        with patch.dict(publisher.os.environ, self.environment), patch.object(publisher.subprocess, "run", return_value=missing), \
             patch.object(publisher, "run", side_effect=run):
            with self.assertRaisesRegex(RuntimeError, "Push failed"):
                publisher.publish(self.directory, self.metadata, self.images)
        self.assertFalse(any(args[0] == "gh" for args in commands))

    def test_release_is_finalized_only_after_both_images_and_manifest(self):
        missing = type("Response", (), {"returncode": 1, "stderr": "HTTP 404"})()
        commands = []
        def run(*args, **kwargs):
            commands.append(args)
        def inspected(tag):
            return {"RepoDigests": [tag.rsplit(":", 1)[0] + "@sha256:" + "e" * 64]}
        with patch.dict(publisher.os.environ, self.environment), patch.object(publisher.subprocess, "run", return_value=missing), \
             patch.object(publisher, "run", side_effect=run), patch.object(publisher, "inspect_image", side_effect=inspected):
            publisher.publish(self.directory, self.metadata, self.images)
        self.assertEqual(sum(args[:2] == ("docker", "push") for args in commands), 6)
        self.assertEqual(commands[-2][:3], ("gh", "release", "create"))
        self.assertIn("--draft", commands[-2])
        self.assertEqual(commands[-1][:3], ("gh", "release", "edit"))
        published = json.loads((self.directory / "release.json").read_text())
        self.assertEqual(set(published["images"]), {"server", "agent"})
        self.assertIn("@sha256:", published["images"]["server"]["reference"])


if __name__ == "__main__":
    unittest.main()
