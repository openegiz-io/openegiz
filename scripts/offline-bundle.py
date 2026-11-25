#!/usr/bin/env python3
"""Export, verify, and restore a portable OpenEgiz Offline Bundle."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = ("linux/amd64", "linux/arm64")
NUMBER = r"(?:0|[1-9][0-9]*)"
IDENTIFIER = rf"(?:{NUMBER}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
RELEASE = re.compile(rf"v{NUMBER}\.{NUMBER}\.{NUMBER}(?:-{IDENTIFIER}(?:\.{IDENTIFIER})*)?")
IMAGE = re.compile(r"[a-z0-9.-]+(?::[0-9]+)?/[a-z0-9._/-]+:[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9_.-]*")
DIGEST = re.compile(r"sha256:[0-9a-f]{64}")
CHECKSUM = re.compile(r"([0-9a-f]{64}) [ *]([^\r\n]+)")
REGISTRY = "ghcr.io/openegiz-io"
CHART_SOURCE = f"oci://{REGISTRY}/charts/openegiz"
MIRROR = "openegiz.git.tar.gz"
HELPER = "offline-bundle.py"
HELM_VALUES = "offline-images.values.json"
WHEEL = "paho_mqtt-2.1.0-py3-none-any.whl"
WHEEL_URL = (
    "https://files.pythonhosted.org/packages/c4/cb/"
    "00451c3cf31790287768bb12c6bec834f5d292eaf3022afc88e14b8afc94/" + WHEEL
)
WHEEL_SHA256 = "6db9ba9b34ed5bc6b6e3812718c7e06e2fd7444540df2455d2c51bd58808feee"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*command, capture=False, **kwargs):
    return subprocess.run(command, check=True, stdout=subprocess.PIPE if capture else None,
                          **kwargs).stdout


def output(*command, **kwargs):
    return run(*command, capture=True, **kwargs).decode().strip()


def sha256(stream):
    sha = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        sha.update(chunk)
    return sha.hexdigest()


def file_sha256(path):
    with path.open("rb") as stream:
        return sha256(stream)


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def version_of(tag):
    require(isinstance(tag, str) and RELEASE.fullmatch(tag) and len(tag) <= 129,
            "Expected a vMAJOR.MINOR.PATCH tag with an optional SemVer prerelease")
    return tag[1:]


def checksums(text):
    entries = {}
    for line in text.splitlines():
        match = CHECKSUM.fullmatch(line)
        require(match, f"Invalid SHA256SUMS entry: {line!r}")
        digest, name = match.groups()
        require(name not in entries, f"Duplicate SHA256SUMS entry: {name}")
        entries[name] = digest
    return entries


def archive_files(archive):
    files = {}
    for member in archive.getmembers():
        name = PurePosixPath(member.name)
        require(member.isfile() and not name.is_absolute() and ".." not in name.parts
                and str(name) == member.name and member.name not in files,
                f"Unexpected archive member: {member.name}")
        files[member.name] = member
    return files


def copy_member(archive, name, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with archive.extractfile(name) as source, path.open("xb") as dest:
        shutil.copyfileobj(source, dest)


def git_mirror(tag, directory):
    ref = f"refs/tags/{tag}"
    require(output("git", "-C", ROOT, "rev-parse", "--is-shallow-repository") == "false",
            "Fetch the full repository history before exporting the Offline Bundle")
    commit = output("git", "-C", ROOT, "rev-parse", "--verify", f"{ref}^{{commit}}")
    mirror = directory / "mirror.git"
    run("git", "init", "--quiet", "--bare", "--template=", mirror)
    run("git", "-C", mirror, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head",
        "--no-recurse-submodules", ROOT, f"{ref}:{ref}")
    run("git", "-C", mirror, "update-ref", "--no-deref", "HEAD", commit)
    run("git", "-C", mirror, "fsck", "--full", "--no-dangling")
    return mirror, commit, output("git", "-C", mirror, "rev-parse", ref)


def clone_release(mirror, tag, checkout):
    run("git", "clone", "--quiet", "--no-local", "--no-checkout", "--", mirror, checkout)
    run("git", "-C", checkout, "checkout", "--quiet", "--detach", f"refs/tags/{tag}")


def chart_archive(args, version, assets, yaml):
    name = f"openegiz-{version}.tgz"
    path = assets / name
    if args.chart:
        expected = checksums(args.chart_checksums.read_text(encoding="utf-8")).get(name)
        require(expected, f"No checksum for {name} in {args.chart_checksums}")
        shutil.copyfile(args.chart, path)
        require(file_sha256(path) == expected, f"Chart checksum mismatch: {name}")
        oci_digest = None
    else:
        try:
            result = output("helm", "pull", CHART_SOURCE, "--version", version,
                            "--destination", assets, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as error:
            raise ValueError(error.output.decode().strip()) from error
        digest = re.search(r"(?m)^Digest:\s+(sha256:[0-9a-f]{64})\s*$", result)
        require(digest, f"Helm did not report an OCI chart digest:\n{result}")
        oci_digest = digest[1]

    metadata = yaml.safe_load(output("helm", "show", "chart", path))
    require(metadata.get("name") == "openegiz" and metadata.get("version") == version
            and metadata.get("appVersion") == version,
            f"Chart name, version and appVersion do not match OpenEgiz {version}")
    return path, oci_digest


def compose_profiles(checkout, version):
    directory = checkout / "deploy/compose"
    # Use the release defaults without importing the exporter's Compose settings.
    env = {key: os.environ[key] for key in ("PATH", "HOME", "DOCKER_CONFIG", "SYSTEMROOT") if key in os.environ}
    env["OPENEGIZ_RELEASE"] = version
    run("bash", checkout / "scripts/compose-env.sh", env=env, cwd=checkout, capture=True)
    compose = ["docker", "compose", "--env-file", directory / ".env",
               "-f", directory / "docker-compose.yml", "-f", directory / "docker-compose.release.yml"]
    prod = compose + ["-f", directory / "docker-compose.prod.yml"]
    for profile, command in (
        ("compose-dev", compose),
        ("compose-production", prod),
        ("compose-production-mqtts", prod + ["-f", directory / "docker-compose.mqtts.yml"]),
    ):
        images = output(*command, "config", "--images", env=env, cwd=checkout)
        yield profile, sorted(set(images.splitlines()))


def helm_policies(values):
    # Capture precisely the existing pull-policy values exposed by the chart.
    if not isinstance(values, dict):
        return {}
    policies = {key: helm_policies(value) for key, value in values.items()}
    policies = {key: value for key, value in policies.items() if value}
    if "pullPolicy" in values:
        policies["pullPolicy"] = "Never"
    return policies


def pod_images(document):
    if not isinstance(document, dict):
        return
    for key in ("containers", "initContainers", "ephemeralContainers"):
        for container in document.get(key, []):
            yield container["image"], container.get("imagePullPolicy")
    for key in ("spec", "template", "jobTemplate"):
        yield from pod_images(document.get(key))
    for item in document.get("items", []):
        yield from pod_images(item)


def helm_profiles(checkout, chart, values_path, yaml):
    defaults = yaml.safe_load(output("helm", "show", "values", chart))
    write_json(values_path, helm_policies(defaults))
    helm = ["helm", "template", "bundle-check", chart, "-n", "bundle-check",
            "--set", "credentials.existingSecret=bundle-check"]

    def render(*flags):
        rendered = output(*helm, *flags)
        return [item for document in yaml.safe_load_all(rendered) for item in pod_images(document)]

    for profile, flags in (("helm-dev", []), ("helm-production", [
        "-f", checkout / "charts/openegiz/values-prod.yaml",
    ])):
        default_images = {image for image, _ in render(*flags)}
        offline = render(*flags, "-f", values_path)
        require({image for image, _ in offline} == default_images
                and all(policy == "Never" for _, policy in offline),
                f"The Offline Bundle values do not preserve images and disable pulls in {profile}")
        yield profile, sorted(default_images)


def platform_manifest(raw, platform):
    document = json.loads(raw)
    if "manifests" not in document:
        return "sha256:" + hashlib.sha256(raw).hexdigest()
    os_name, arch = platform.split("/")
    baseline_variant = {"arm64": "v8", "amd64": "v1"}[arch]
    candidates = [
        entry["digest"]
        for entry in document["manifests"]
        if (spec := entry.get("platform", {})).get("os") == os_name
        and spec.get("architecture") == arch and spec.get("variant", "") in ("", baseline_variant)
    ]
    require(len(set(candidates)) == 1, f"Expected one base manifest for {platform}, found {candidates}")
    return candidates[0]


def image_archive_path(image, platform):
    name = image.replace("/", "_").replace(":", "-")
    return f"images/{platform.replace('/', '-')}/{name}.tar"


def image_blob(archive, digest):
    require(DIGEST.fullmatch(digest), f"Unsupported image blob digest: {digest}")
    raw = archive.extractfile("blobs/" + digest.replace(":", "/", 1)).read()
    require(hashlib.sha256(raw).hexdigest() == digest.split(":")[1],
            f"Image blob digest mismatch: {digest}")
    return json.loads(raw)


def export_image(assets, platforms, image):
    repository = image.rsplit(":", 1)[0]
    raw = run("regctl", "manifest", "get", image, "--format", "raw-body", capture=True)
    index_digest = "sha256:" + hashlib.sha256(raw).hexdigest()
    entries = {}
    for platform in platforms:
        digest = platform_manifest(raw, platform)
        require(DIGEST.fullmatch(digest), f"Unsupported image digest: {digest}")
        name = image_archive_path(image, platform)
        path = assets / name
        print(f"Exporting {image} ({platform}, {digest})", flush=True)
        run("regctl", "image", "export", f"{repository}@{digest}", path, "--name", image)
        with tarfile.open(path, "r:") as archive:
            descriptor, = json.load(archive.extractfile("index.json"))["manifests"]
            require(descriptor["digest"] == digest, f"Image manifest digest mismatch: {image}")
            require(descriptor["annotations"]["io.containerd.image.name"] == image,
                    f"Image archive has the wrong containerd name: {image}")
            docker_entry, = json.load(archive.extractfile("manifest.json"))
            require(docker_entry["RepoTags"] == [image], f"Image archive has the wrong Docker tag: {image}")
            config = image_blob(archive, digest)["config"]["digest"]
            metadata = image_blob(archive, config)
            require(f"{metadata['os']}/{metadata['architecture']}" == platform,
                    f"Unexpected image architecture: {image}, expected {platform}")
        entries[platform] = {"archive": name, "manifest_digest": digest, "config_digest": config}
    return {"index_digest": index_digest, "platforms": entries}


def export_images(assets, images, platforms):
    for platform in platforms:
        paths = {image_archive_path(image, platform) for image in images}
        require(len(paths) == len(images), f"Image archive name collision for {platform}")
        (assets / next(iter(paths))).parent.mkdir(parents=True)
    with ThreadPoolExecutor(max_workers=3) as pool:
        try:
            exports = pool.map(lambda image: export_image(assets, platforms, image), images)
            return dict(zip(images, exports))
        finally:
            pool.shutdown(cancel_futures=True)


def export_bundle(args):
    try:
        import yaml
    except ImportError as error:
        raise ValueError("Export requires PyYAML. See docs/offline-bundle.md.") from error

    version = version_of(args.tag)
    require(bool(args.chart) == bool(args.chart_checksums),
            "--chart and --chart-checksums must be supplied together")
    platforms = sorted(set(args.platform))
    now = datetime.now(timezone.utc)
    name = f"openegiz-{version}-{now:%Y%m%dT%H%M%S%fZ}.tar"
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".openegiz-export-", dir=destination) as directory:
        work = Path(directory)
        assets = work / "assets"
        assets.mkdir()
        mirror, commit, tag_object = git_mirror(args.tag, work)
        checkout = work / "source"
        clone_release(mirror, args.tag, checkout)
        with tarfile.open(assets / MIRROR, "w:gz") as archive:
            for path in sorted(mirror.rglob("*")):
                if path.is_file():
                    archive.add(path, arcname=path.relative_to(mirror).as_posix())

        chart, oci_digest = chart_archive(args, version, assets, yaml)
        profiles = dict(compose_profiles(checkout, version))
        profiles.update(helm_profiles(checkout, chart, assets / HELM_VALUES, yaml))
        for profile, images in profiles.items():
            require(images, f"No container images were rendered for {profile}")
            for name_part in ("extended-api", "grafana-plugins"):
                require(f"{REGISTRY}/{name_part}:{version}" in images,
                        f"{profile} did not render the released {name_part} image")
        images = sorted({image for profile in profiles.values() for image in profile},
                        key=lambda image: (not image.startswith(f"{REGISTRY}/"), image))
        require(all(IMAGE.fullmatch(image) for image in images),
                f"Expected fully qualified, version-pinned image references: {images}")
        run("curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "60",
            "--output", assets / WHEEL, WHEEL_URL)
        require(file_sha256(assets / WHEEL) == WHEEL_SHA256, f"Checksum mismatch: {WHEEL}")
        manifest = {
            "format_version": 1,
            "created_at": now.isoformat(timespec="seconds"),
            "release": {"tag": args.tag, "version": version, "commit": commit, "tag_object": tag_object},
            "platforms": platforms,
            "chart": {"archive": chart.name, "source": CHART_SOURCE if oci_digest else "local",
                      "oci_digest": oci_digest, "sha256": file_sha256(chart)},
            "profiles": profiles,
            "images": export_images(assets, images, platforms),
        }
        shutil.copyfile(Path(__file__).resolve(), assets / HELPER)
        write_json(assets / "manifest.json", manifest)

        # Hash and write each artifact in one pass to avoid rereading the image set.
        staged = work / name
        entries = {}
        with tarfile.open(staged, "w:") as archive:
            for path in sorted(assets.rglob("*")):
                if path.is_file():
                    member = path.relative_to(assets).as_posix()
                    with path.open("rb") as stream:
                        sha = hashlib.sha256()

                        class HashingReader:
                            def read(self, size):
                                chunk = stream.read(size)
                                sha.update(chunk)
                                return chunk

                        archive.addfile(archive.gettarinfo(str(path), arcname=member), HashingReader())
                    entries[member] = sha.hexdigest()
            checksum_path = work / "SHA256SUMS"
            checksum_path.write_text("".join(f"{digest}  {member}\n" for member, digest in entries.items()),
                                     encoding="utf-8")
            archive.add(checksum_path, arcname="SHA256SUMS")
        staged.rename(destination / name)
    print(destination / name)


def validate_manifest(manifest, entries):
    require(manifest["format_version"] == 1, "Unsupported Offline Bundle format")
    version = version_of(manifest["release"]["tag"])
    require(manifest["release"]["version"] == version, "Release version does not match the tag")
    for key in ("commit", "tag_object"):
        require(re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", manifest["release"][key]),
                f"Invalid Git {key}")
    platforms = manifest["platforms"]
    require(platforms and platforms == sorted(set(platforms)) and set(platforms) <= set(PLATFORMS),
            "Invalid Offline Bundle platforms")
    chart = manifest["chart"]["archive"]
    require(chart == f"openegiz-{version}.tgz" and entries.get(chart) == manifest["chart"]["sha256"],
            "Invalid chart archive or checksum")
    digest = manifest["chart"]["oci_digest"]
    require(digest is None or DIGEST.fullmatch(digest), "Invalid OCI chart digest")
    require(entries.get(WHEEL) == WHEEL_SHA256, f"Invalid checksum for {WHEEL}")
    images = manifest["images"]
    require(images and set(images) == {image for profile in manifest["profiles"].values() for image in profile},
            "Image inventory does not match the Deployment Profiles")
    expected = {MIRROR, HELPER, HELM_VALUES, WHEEL, chart, "manifest.json"}
    for image, inventory in images.items():
        require(IMAGE.fullmatch(image), f"Invalid image reference: {image}")
        require(DIGEST.fullmatch(inventory["index_digest"]), f"Invalid image index digest: {image}")
        require(set(inventory["platforms"]) == set(platforms), f"Missing image platforms: {image}")
        for platform, item in inventory["platforms"].items():
            name = image_archive_path(image, platform)
            require(item["archive"] == name and name not in expected
                    and DIGEST.fullmatch(item["manifest_digest"]) and DIGEST.fullmatch(item["config_digest"]),
                    f"Invalid image inventory: {image} ({platform})")
            expected.add(name)
    require(expected == set(entries), "Manifest inventory does not match SHA256SUMS")


@contextmanager
def verified_bundle(path):
    with tarfile.open(path, "r:") as archive:
        files = archive_files(archive)
        require("SHA256SUMS" in files, "Offline Bundle has no SHA256SUMS")
        entries = checksums(archive.extractfile("SHA256SUMS").read().decode())
        require(set(entries) == files.keys() - {"SHA256SUMS"}, "SHA256SUMS does not cover every artifact")
        for name, expected in entries.items():
            with archive.extractfile(name) as stream:
                require(sha256(stream) == expected, f"Checksum mismatch: {name}")
        manifest = json.load(archive.extractfile("manifest.json"))
        validate_manifest(manifest, entries)
        print(f"Verified {manifest['release']['tag']} ({', '.join(manifest['platforms'])}): "
              f"{len(entries)} artifacts", flush=True)
        yield archive, manifest


def restore_checkout(archive, manifest, checkout):
    checkout = checkout.absolute()
    checkout.parent.mkdir(parents=True, exist_ok=True)
    release = manifest["release"]
    with tempfile.TemporaryDirectory(prefix=".openegiz-restore-", dir=checkout.parent) as directory:
        work = Path(directory)
        copy_member(archive, MIRROR, work / MIRROR)
        mirror = work / "mirror.git"
        with tarfile.open(work / MIRROR, "r:gz") as source:
            for name in archive_files(source):
                copy_member(source, name, mirror / name)
        ref = f"refs/tags/{release['tag']}"
        require(output("git", "-C", mirror, "for-each-ref", "--format=%(refname)") == ref,
                "The bare Git mirror must contain only the requested tag")
        require(output("git", "-C", mirror, "rev-parse", f"{ref}^{{commit}}") == release["commit"]
                and output("git", "-C", mirror, "rev-parse", ref) == release["tag_object"],
                "Git tag or commit does not match the manifest")
        run("git", "-C", mirror, "fsck", "--full", "--no-dangling")
        staged = work / "checkout"
        clone_release(mirror, release["tag"], staged)
        run("git", "-C", staged, "remote", "remove", "origin")
        for name in (manifest["chart"]["archive"], HELM_VALUES, WHEEL, HELPER, "manifest.json"):
            copy_member(archive, name, staged / ".offline" / name)
        staged.rename(checkout)
    print(f"Restored {release['tag']} into {checkout}")


def restore_images(archive, manifest, platform, runtime):
    docker = runtime == "docker"
    prefix = "compose-" if docker else "helm-"
    images = sorted({image for profile, images in manifest["profiles"].items()
                     if profile.startswith(prefix) for image in images})
    require(images, f"No {prefix.removesuffix('-')} images in this Offline Bundle")
    ctr = (["k3s"] if runtime == "k3s" else []) + ["ctr", "--namespace", "k8s.io", "images"]
    for image in images:
        item = manifest["images"][image]["platforms"][platform]
        print(f"Loading {image} ({platform}) into {runtime}", flush=True)
        with archive.extractfile(item["archive"]) as stream:
            command = ["docker", "image", "load"] if docker else ctr + ["import", "--platform", platform, "-"]
            with subprocess.Popen(command, stdin=subprocess.PIPE) as process:
                try:
                    shutil.copyfileobj(stream, process.stdin, length=1024 * 1024)
                except BrokenPipeError:
                    pass
            require(process.returncode == 0, f"{runtime} could not import {image}")
        if docker:
            image_id, actual_platform = output(
                "docker", "image", "inspect", "--format", "{{.Id}} {{.Os}}/{{.Architecture}}", image
            ).split()
            # Docker's classic store reports the config digest. Its containerd
            # store reports the image manifest digest for this archive.
            require(actual_platform == platform and image_id in (item["config_digest"], item["manifest_digest"]),
                    f"Unexpected Docker image: {image}")

    if not docker:
        loaded = {}
        for line in output(*ctr, "list").splitlines()[1:]:
            columns = line.split()
            loaded[columns[0]] = columns[2]
        for image in images:
            digest = manifest["images"][image]["platforms"][platform]["manifest_digest"]
            require(loaded.get(image) == digest,
                    f"Unexpected containerd image: {image}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export", help="export a local release tag and its published artifacts")
    export.add_argument("--tag", required=True, help="local release tag (vMAJOR.MINOR.PATCH[-PRERELEASE])")
    export.add_argument("--platform", choices=PLATFORMS, action="append", required=True,
                        help="Linux platform to archive, repeat to include both")
    export.add_argument("--output", type=Path, required=True, help="directory for the versioned .tar")
    export.add_argument("--chart", type=Path, help="local packaged release chart")
    export.add_argument("--chart-checksums", type=Path, help="SHA256SUMS accompanying --chart")

    verify = commands.add_parser("verify", help="verify the bundle and all artifact checksums")
    verify.add_argument("bundle", type=Path)

    restore = commands.add_parser("restore", help="verify and recover the release checkout and/or load images")
    restore.add_argument("bundle", type=Path)
    restore.add_argument("--checkout", type=Path, help="new directory for the release and .offline assets")
    restore.add_argument("--runtime", choices=("docker", "k3s", "containerd"))
    restore.add_argument("--platform", choices=PLATFORMS, help="native Linux platform of the target runtime")

    args = parser.parse_args()
    if args.command == "restore" and (
        not (args.checkout or args.runtime) or bool(args.runtime) != bool(args.platform)
    ):
        restore.error("specify --checkout and/or both --runtime and --platform")
    try:
        if args.command == "export":
            export_bundle(args)
        else:
            with verified_bundle(args.bundle) as (archive, manifest):
                if args.command == "restore":
                    if args.checkout:
                        require(not (args.checkout.exists() or args.checkout.is_symlink()),
                                f"Checkout already exists: {args.checkout}")
                    if args.runtime:
                        require(args.platform in manifest["platforms"],
                                f"{args.platform} is unavailable in this Offline Bundle")
                        restore_images(archive, manifest, args.platform, args.runtime)
                    if args.checkout:
                        restore_checkout(archive, manifest, args.checkout)
    except (KeyError, OSError, TypeError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print(f"Offline Bundle error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
