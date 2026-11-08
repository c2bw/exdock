#!/usr/bin/env python3
"""Publish the exported, tested image pair; --check validates without publishing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile


def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def archive_image_ids(archive):
    """Configuration digests identify image content across Docker image stores."""
    with tarfile.open(archive) as contents:
        manifest = json.load(contents.extractfile("manifest.json"))
        identities = {}
        for image in manifest:
            config = contents.extractfile(image["Config"]).read()
            identity = "sha256:" + hashlib.sha256(config).hexdigest()
            for tag in image.get("RepoTags") or []:
                if tag in identities:
                    raise ValueError("Duplicate image tag in archive")
                identities[tag] = identity
        return identities


def record_image_ids(directory):
    images = json.loads((directory / "images.json").read_text())
    identities = archive_image_ids(directory / "images.tar")
    for kind in ("server", "agent"):
        image = images[kind]
        image["source_image_id"] = image["id"]
        image["id"] = identities[image["local_tag"]]
    (directory / "images.json").write_text(json.dumps(images, indent=2) + "\n")


def validate(directory, inspect_image):
    metadata = json.loads((directory / "release.json").read_text())
    images = json.loads((directory / "images.json").read_text())
    version = metadata["version"]
    revision = metadata["revision"]
    repository = metadata["repository"]
    if metadata["schema_version"] != 1 or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version/schema")
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("Invalid source revision")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_.-]*/[a-z0-9][a-z0-9_.-]*", repository):
        raise ValueError("Invalid repository")
    if metadata["tag"] != "v" + version or metadata["source"] != "https://github.com/" + repository:
        raise ValueError("Release tag/source mismatch")
    if metadata["platform"] != "linux/amd64":
        raise ValueError("Only the tested linux/amd64 release is supported")
    if any(metadata["packages"][kind] != version for kind in ("server", "agent")):
        raise ValueError("Package versions must match the release")
    expected_revision = revision + ("-dirty" if metadata["dirty"] else "")
    if metadata["image_revision"] != expected_revision:
        raise ValueError("Image revision does not match source state")
    for kind in ("server", "agent"):
        tag = "ghcr.io/" + repository + ("_client" if kind == "agent" else "") + ":" + metadata["tag"]
        if metadata["image_tags"][kind] != tag:
            raise ValueError("Unexpected registry tag")
        if images[kind]["local_tag"] != "suite-" + kind + ":local":
            raise ValueError("Unexpected exported image name")
        image = inspect_image(images[kind]["local_tag"])
        if image["Id"] != images[kind]["id"] or image["Os"] != "linux" or image["Architecture"] != "amd64":
            raise ValueError("Exported image identity/platform mismatch")
        labels = image["Config"]["Labels"]
        expected = {"version": version, "revision": expected_revision,
                    "source": metadata["source"], "licenses": "MIT", "title": "Exdock " + kind}
        if any(labels.get("org.opencontainers.image." + key) != value for key, value in expected.items()):
            raise ValueError("Image labels do not match release metadata")
    return metadata, images


def require_publish_context(metadata, environment):
    if metadata["dirty"]:
        raise ValueError("Cannot publish a dirty working tree")
    if environment.get("GITHUB_REF") != "refs/tags/" + metadata["tag"]:
        raise ValueError("Publication requires the matching release tag")
    if environment.get("GITHUB_SHA") != metadata["revision"]:
        raise ValueError("Publication revision does not match the workflow")
    if environment.get("GITHUB_REPOSITORY", "").lower() != metadata["repository"]:
        raise ValueError("Publication repository does not match the workflow")


def inspect_image(tag):
    image = json.loads(run("docker", "image", "inspect", tag, capture=True))[0]
    # Containerd-backed stores expose an OCI index digest as Id, while classic
    # stores expose a configuration digest. Re-export the loaded image and hash
    # its original config bytes, which also bind its rootfs layer digests.
    with tempfile.TemporaryDirectory(prefix="exdock-image-identity-") as directory:
        archive = Path(directory) / "image.tar"
        run("docker", "image", "save", "--output", str(archive), tag)
        image["Id"] = archive_image_ids(archive)[tag]
    return image


def publish(directory, metadata, images):
    require_publish_context(metadata, os.environ)
    # Existing public releases and abandoned drafts require explicit maintainer review.
    existing = subprocess.run(["gh", "api", "repos/" + metadata["repository"] +
                               "/releases/tags/" + metadata["tag"]], text=True, capture_output=True)
    if existing.returncode == 0:
        raise ValueError("A release/draft already exists; do not reuse published versions")
    if "HTTP 404" not in existing.stderr:
        raise RuntimeError("Unable to check whether the release already exists")

    published = {}
    # Push both commit tags before exposing either version tag. Registry pushes
    # are not atomic; the public GitHub release is finalized only after both succeed.
    for kind in ("server", "agent"):
        version_tag = metadata["image_tags"][kind]
        commit_tag = version_tag.rsplit(":", 1)[0] + ":sha-" + metadata["revision"]
        run("docker", "tag", images[kind]["local_tag"], commit_tag)
        run("docker", "push", commit_tag)
        published[kind] = {"tag": version_tag, "commit_tag": commit_tag, "image_id": images[kind]["id"]}

    for kind in ("server", "agent"):
        tag = published[kind]["tag"]
        run("docker", "tag", images[kind]["local_tag"], tag)
        run("docker", "push", tag)
        repository = tag.rsplit(":", 1)[0]
        matches = [value for value in inspect_image(tag).get("RepoDigests", []) if value.startswith(repository + "@sha256:")]
        if len(matches) != 1:
            raise ValueError("Unable to identify published registry digest")
        published[kind]["digest"] = matches[0].split("@", 1)[1]
        published[kind]["reference"] = tag + "@" + published[kind]["digest"]

    # Keep the existing Compose examples usable. These convenience aliases are
    # promoted only after both tested version tags are present; use version tags
    # or digest references when coordinating upgrades across hosts.
    for kind in ("server", "agent"):
        latest = published[kind]["tag"].rsplit(":", 1)[0] + ":latest"
        run("docker", "tag", images[kind]["local_tag"], latest)
        run("docker", "push", latest)
        published[kind]["latest_alias"] = latest

    metadata["images"] = published
    (directory / "release.json").write_text(json.dumps(metadata, indent=2) + "\n")
    with (directory / "release-notes.md").open("a") as notes:
        notes.write("\n\n### Published image pair\n\n")
        for kind in ("server", "agent"):
            notes.write("- " + kind + ": `" + published[kind]["reference"] + "`\n")
        notes.write("\nSource revision: `" + metadata["revision"] + "`. See `release.json` for compatibility and base images.\n")
    assets = [directory / name for name in ("release.json", "images.json", "tested-engine.txt", "compose.release.yml", ".env.example")]
    run("gh", "release", "create", metadata["tag"], "--repo", metadata["repository"],
        "--verify-tag", "--draft", "--title", "Exdock " + metadata["tag"],
        "--notes-file", str(directory / "release-notes.md"), *map(str, assets))
    run("gh", "release", "edit", metadata["tag"], "--repo", metadata["repository"], "--draft=false", "--latest")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--record-image-identities", action="store_true",
                      help="Record portable content identities from the tested image archive")
    args = parser.parse_args()
    if args.record_image_identities:
        record_image_ids(args.directory)
        return
    if not args.check:
        # Reject branch events/dirty metadata before loading anything into Docker.
        require_publish_context(json.loads((args.directory / "release.json").read_text()), os.environ)
    run("docker", "load", "--input", str(args.directory / "images.tar"))
    metadata, images = validate(args.directory, inspect_image)
    if args.check:
        print("Exported image IDs, labels, platform, and release metadata match; nothing published")
    else:
        publish(args.directory, metadata, images)


if __name__ == "__main__":
    main()
