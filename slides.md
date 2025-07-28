---
theme: default
title: Welcome to Slidev
info: |
  ## NixOS for the Asahi Installer
class: text-center
drawings:
  persist: false
transition: fade-out
mdc: true
---

# NixOS for the Asahi Installer

Enabling Automated NixOS Installation on Apple Silicon Macs

Quinn Edenfield

<div @click="$slidev.nav.next" class="mt-12 py-1 px-3 inline-block rounded" hover:bg="white op-5">
  Press <kbd>right</kbd> or <kbd>space</kbd> for next page <carbon:arrow-right />
</div>

<div class="abs-br m-6 text-xl">
  <a href="https://github.com/quinneden/nixos-asahi-package" target="_blank" class="slidev-icon-btn">
    <carbon:logo-github />
  </a>
</div>

<!--
Hi everyone, my name is Quinn Edenfield. Thank you for giving me this opportunity to walk you through a project of mine, `nixos-asahi-package`, and showcase my approach to solving complex system integration problems and automation challenges. We'll cover NixOS disk image generation, package transformation, and CI/CD automation to create a one-command OS install process for deploying NixOS onto Apple Silicon Macs.
-->

---
transition: fade-out
---

# The Problem

Before `nixos-asahi-package`, installing NixOS on an Apple Silicon Mac was a complex process involving manual partitioning and hours of debugging.


<div v-click="1">

**The Core Technical Challenge:** How to programmatically build a bootable, custom NixOS disk image and package it for a third-party installer (`asahi-installer`) so that it is ready to be installed onto bare metal, all within a fully automated CI/CD pipeline?

</div>

<div v-click="2">

This breaks down into three sub-problems:

<br>
</div>

<div v-click="3" class="grid grid-cols-3 gap-4">

<div v-motion
  :initial="{ opacity: 0 }"
  :click-3="{ opacity: 1, transition: { delay: 200, duration: 800 } }"
  class="col-span-1">

1. **Declarative Image Generation:**<br>
How to create raw, bootable `aarch64-linux` NixOS disk images for multiple filesystem variants declaratively?

</div>

<div v-motion
  :initial="{ opacity: 0 }"
  :click-3="{ opacity: 1, transition: { delay: 1000, duration: 800 } }"
  class="col-span-1">

2. **Format Transformation:**<br>
How to deconstruct this image into the specific image/directory structure required by the installer?

</div>

<div v-motion
  :initial="{ opacity: 0 }"
  :click-3="{ opacity: 1, transition: { delay: 1800, duration: 800 } }"
  class="col-span-1">

3. **Automated Distribution:**<br>
How to automate the entire build, transformation, and release process to a public CDN on every version bump?

</div>

</div>

<!--
The goal was to make NixOS on Apple Silicon more accessible. But the technical hurdle was significant. I had two disconnected worlds: the world of Nix & NixOS, which is great at producing declarative, reproducible system configurations, and the Asahi Installer, which is the only tool available that can safely partition a Mac's internal drive and bless a new Linux OS.

The installer doesn't accept a standard disk image as it's payload. It requires a specific set of files: a zipped archive containing a disk image of a root partition, and the contents of an ESP partition extracted into a directory, and a JSON manifest file that describes the content and structure of the installer payload. My goal was to bridge these two worlds and automate the entire process.
-->

---
transition: fade-out
layout: two-cols-header
layoutClass: gap-4
clicks: 5
---

# The Solution

A pipeline to transform source code into a NixOS package and hosted installer to facilitate installation onto Apple Silicon hardware with minimal manual intervention.

::left::

<div class="text-xs">

1. **`nix run .#create-release`:** A Nix Flake app that pushes a version tag to the `main` branch.

<div v-click="1" class="fade-in">

2. **GitHub Actions:** That push triggers a CI/CD workflow which uses `nix-fast-build` to evaluate and build the package variants concurrently.

</div>

<div v-click="2" class="fade-in">

3. **Nix Build:** The build process begins with creating the NixOS disk images, one using `btrfs` and the other using `ext4`.

</div>

<div v-click="3" class="fade-in">

4. **Package & Transform:** Once the images are built, the next step deconstructs the `.img` files into `.zip` archives and generates JSON manifests for the installer.

</div>

<div v-click="4" class="fade-in">

5.  **Deploy:** Then, a python script uploads the final artifacts to a Cloudflare R2 bucket, which are then served, along with the installer bootstrap scripts, via `https://cdn.nixos-asahi.qeden.dev`.

</div>

<div v-click="5" class="fade-in">

6.  **User Install:** The user runs `curl -L https://nixos-asahi.qeden.dev/install | sh`, which executes the bootstrap script, subsequently fetching the installer and the metadata from the CDN to install the OS.

</div>

</div>

::right::

````markdown magic-move {style: 'min-width: 450px; max-width: 450px; overflow: auto; display: block; background: var(--slidev-code-background, #1e1e1e); padding: 0.5rem; border-radius: 0.375rem;'}
```bash
#  create-release.sh:

#  ...truncated...
sed -i "s/commits = [0-9]\+;/commits = $commit_count;/g" version.nix
sed -i "s/released = false/released = true/g" version.nix

git commit -am "release: v$version"
git tag -a "v$version" -m "release: v$version"
git tag -fa "latest" -m "release: v$version"

sed -i "s/released = true;/released = false;/g" version.nix
git commit -am "chore(version.nix): reset released flag"

echo "Release was prepared successfully!"
echo "To push the release, run the following command:"
echo
echo "  git push origin main v$version && git push --force origin latest"
```

```yaml
on:
  workflow_dispatch:
  push:
    tags:
      - "v[0-9]*.[0-9]*.[0-9]*"
#  ...truncated...
    steps:
    #  ...truncated...
      - name: Build metapackage
        run: |
          nix-fast-build \
            --eval-workers 24 \
            --eval-max-memory-size 8192 \
            --skip-cached \
            --no-nom
```

```nix
copyStagingRoot =
  if fsType == "btrfs" then
    # ... truncated ...
  else 
    # ... truncated ...

buildImageStageOne = pkgs.vmTools.runInLinuxVM (
    pkgs.runCommand "${name}-stage-one" (
      # ... truncated...
    )
);

buildImageStageTwo = pkgs.vmTools.runInLinuxVM (
    pkgs.runCommand name (
    #  ... truncated...
    )
);
```

```nix
#  ...truncated...
buildPhase = ''
  #  ...
  eval "$(fdisk -Lnever -lu -b 512 "$diskImage" \
    | awk "/^$diskImage/ { printf \"dd if=$diskImage of=%s skip=%s count=%s bs=512\\n\", \$1, \$2, \$4 }")"

  mkdir -p package/esp
  7z x -o"package/esp" "''${diskImage}1"
  mv "''${diskImage}2" package/root.img
  pushd package/ > /dev/null
  rm -rf esp/EFI/nixos/.extra-files
  echo -n 'creating compressed archive:'
  7z a -tzip -r -mx1 -bso0 ../"$pkgZip" ./.
  popd > /dev/null
  jq -r <<< ${lib.escapeShellArg installerData} > "$installerData"
  #  ...
'';
#  ...truncated...
```

```python
#  ...truncated...
def upload_to_r2(file: Path, content_type: str):
    s3_client = boto3.client(
    #  ...truncated...
    with open(file, "rb") as file_bytes:
        s3_client.upload_fileobj(
            file_bytes,
            Bucket=os.getenv("BUCKET_NAME"),
            Callback=progress.update,
            ExtraArgs={"ContentType": content_type},
            Key=object_key,
        )
```

```bash
#  ...truncated...
curl --no-progress-meter -L -o "$PKG" "$INSTALLER_BASE/$PKG"
if ! curl --no-progress-meter -L -O "$INSTALLER_DATA"; then
  #  ...truncated...
fi

echo "  Extracting..."

tar xf "$PKG"

echo "  Initializing..."

if [ "$USER" != "root" ]; then
  echo "The installer needs to run as root."
  echo "Please enter your sudo password if prompted."
  exec caffeinate -dis sudo -E ./install.sh "$@"
else
  exec caffeinate -dis ./install.sh "$@"
fi
```

````

<!--
This is the high-level architecture of the project. It's a classic CI/CD pipeline, but the complexity is hidden in steps 3 and 4, which I'll go into later.

I adapted logic from a similar image-builder script in the nixpkgs repository, with heavy modifications to support both ext4 and btrfs. I wrote the packaging logic and Nix functions to generate installer data from scratch, and configured the GitHub Actions workflow and Python script for the final deployment to the cloud.

Let's zoom in on the most challenging part: building and packaging the image.
-->

---
transition: fade-out
layout: two-cols
layoutClass: gap-4
---

# Building

Building the `btrfs` and `ext4` Image Variants

<div class="text-sm">

<v-clicks>

**Challenge:** An environment capable of producing hermetic, deterministic builds was required, but creating the filesystems and partitioning the disk images required access to system-level resources, like virtual block devices.

**Solution:** A two-stage build process inside a QEMU virtual machine, orchestrated entirely by Nix.

This approach guarantees that the build is reproducible and independent of the host OS, by creating a hermetic Linux environment just for the filesystem-sensitive operations.

</v-clicks>

</div>

::right::

<div v-click="2" class="fade-in">

```nix {style: 'max-width: 450px; overflow: auto; display: block; background: var(--slidev-code-background, #1e1e1e); padding: 0.5rem; border-radius: 0.375rem;'}
prepareStagingRoot = ''
  # Use nixos-install to populate a directory with the full NixOS closure
  # This allows us to later copy it into the disk image and set file
  # modification times deterministically.
  
  nixos-install \
    --root $PWD/root \
    --no-bootloader \
    --system ${config.system.build.toplevel}
'';
#  ... truncated ...
buildImageStageOne = pkgs.vmTools.runInLinuxVM (
  pkgs.runCommand "stage-one" { ... } ''
    #  Inside the VM, we have a block device (/dev/vda)
    mkfs.btrfs -L nixos /dev/vda2
    #  Mount and create btrfs subvolumes for /, /nix, /home
    btrfs subvolume create /mnt/@
    #  ... truncated ...
    #  Copy the prepared rootfs into the newly formatted filesystem
    cptofs -p -P 2 -t btrfs -i $diskImage $root/* /@
  '';
);
```

</div>

<style>
.fade-in {
  transition: opacity 0.3s ease-in-out;
}
</style>

<!--
Here's where I apply first principles. The problem: I need to create a bootable disk image with a specific filesystem layout, but I can't just run `mkfs.btrfs` or `mkfs.ext4` on the host machine. The Nix build environment is sandboxed and doesn't allow mounting filesystems or accessing block devices directly, not to mention I was also developing on a Mac. However, the `mkfs.btrfs` tool doesn't allow specifying the offset of the partition, like `mkfs.ext4` does. This means we need access to virtual block devices to mount the partitions in order to create the filesystems.

First, outside the VM, we use `nixos-install` to populate a directory as a 'staging root' of the NixOS system. This way we only need to run the command once for both image variants, and it allows us to set file modification times deterministically when copied into the image later on.

Second, a QEMU virtual machine is booted. Nix handles spinning up the VM and passing in the staging root and disk image. Inside this hermetic Linux environment, the filesystems are created. Then, after leaving the VM, the staging root is copied into the newly formatted root filesystems. This uses cptofs to deterministically copy to staging root into to root filesystem on the image. Then, a second VM is booted which mounts the two partitions and runs `nixos-enter` and `switch-to-configuration` to activate the NixOS installation.
-->

---
transition: fade-out
layout: two-cols
layoutClass: gap-16
---

# Packaging

The Packaging & Transformation Derivation

<v-clicks>

The `asahi-installer` doesn't accept a disk image. It needs a `.zip` of the rootfs and a JSON file describing the contents of the package.

**Challenge:** How to controllably *deconstruct* the `.img` file that was just carefully built.

**Solution:** A Nix derivation that uses low-level command-line tools to perform the transformation.

This derivation is a micro-factory: it takes in a disk image and outputs a zip file and a JSON file using a precise chain of standard tools to perform a highly specific transformation.

</v-clicks>

::right::

<div v-click="3" class="fade-in" style="transform: scale(0.9);">

```nix
stdenv.mkDerivation {
  # ... truncated ...
  nativeBuildInputs = [ gawk jq p7zip util-linux ];

  buildPhase = ''
    diskImage="${image.name}.img"

    eval "$(
      fdisk -Lnever -lu -b 512 "$diskImage" \
        | awk "/^$diskImage/ 
          {
            printf \"dd if=$diskImage of=%s skip=%s
            count=%s bs=512\\n\", \$1, \$2, \$4 
          }"
    )"

    7z x -o"package/esp" "''${diskImage}1"
    mv "''${diskImage}2" package/root.img

    7z a -tzip -r ../"$pkgZip" ./package

    jq -r <<< ${lib.escapeShellArg installerData} \
      > "$installerData"
  '';
  # ... truncated ...
}
```

</div>

<style>
.fade-in {
  transition: opacity 0.3s ease-in-out;
}
</style>

<!--
So we have the `nixos.img` file, but it's not ready for the Asahi Installer yet. It has to be torn apart again, but in a very controlled way.

Inside another Nix derivation, a sequence of low-level tools is used to do this. Since Nix build environments are sandboxed and don't allow mounting images, we use `fdisk` and `awk` to parse the image's partition table and dynamically generated `dd` commands to carve out each partition into its own separate file.

Next, we use `7zip` to extract the contents of the ESP partition image into a directory. For the root partition image, the file is renamed to `root.img` as required by the installer.

Finally, `7zip` creates a compressed archive containing the `esp` and `root.img`, and `jq` pretty-prints the installer data (which is generated by a nix function in `lib/generate-installer-data.nix`). This two artifacts are the final output of the build process.
-->

---
transition: fade-out
layoutClass: gap-16
layout: two-cols
clicks: 3
---

# CI/CD

The GitHub Actions Workflow that automates the package builds, artifact uploads, and release.

<div class="text-sm">

The workflow triggers on manual dispatch or semantic version tags, running on a self hosted `aarch64-linux` runner.

<div v-click="1" class="fade-in">

Use `nix-fast-build` with aggressive parallelization to handle evaluating the multiple package variants concurrently. Cachix integration provides binary caching, configured to push to the project's associated cache.

</div>

<div v-click="2" class="fade-in">

The workflow uploads both installer data JSON and compressed package archives as release artifacts, then synchronizes them to a Cloudflare R2 storage bucket. This dual strategy ensures reliability while providing the low-latency access required for the installer's download operations.

</div>

</div>

::right::

#### `build-and-release.yml`:

````md magic-move
```yaml
name: Build package and release

on:
  workflow_dispatch:
  push:
    tags:
      - "v[0-9]*.[0-9]*.[0-9]*"

jobs:
  build:
    runs-on:
      labels: oc-runner

    permissions:
      id-token: "write"
      contents: "write"
```

```yaml
steps:
  - uses: actions/checkout@v4.2.2

  - uses: cachix/cachix-action@v16
    with:
      name: nixos-asahi
      authToken: "${{ secrets.CACHIX_AUTH_TOKEN }}"

  - name: Build metapackage
    run: |
      nix-fast-build \
        --eval-workers 24 \
        --eval-max-memory-size 8192 \
        --skip-cached \
        --no-nom
```

```yaml
steps:
  # ...
  - name: Release
    uses: softprops/action-gh-release@v2.2.2
    if: startsWith(github.ref, 'refs/tags/')
    with:
      draft: true
      files: |
        result-aarch64-linux/installer_data-*.json
        result-aarch64-linux/nixos-asahi-*.zip
  
  - name: Upload to CDN
    if: startsWith(github.ref, 'refs/tags/')
    run: |
      touch ./.env
      cat > .env <<EOF
      export ACCESS_KEY_ID=${{ ... }}
      export BASE_URL="https://cdn.qeden.dev"
      export BUCKET_NAME="nixos-asahi"
      export ENDPOINT_URL=${{ ... }}
      export SECRET_ACCESS_KEY=${{ ... }}
      EOF
  
      nix run .#upload -- ./result-aarch64-linux
```
````

<!--
Now I'll dive deeper into the CI/CD process. This workflow is designed around the resource constraints of building full NixOS disk images. At the time of creation, arm64-linux GitHub-hosted runners were not available - so thankfully I had an Oracle Cloud Instance at my disposal. The `oc-runner` label targets my self-hosted runner. The version tag trigger ensures we only run the workflow for properly tagged versions, which are created using the `create-release` flake app.

The build step uses `nix-fast-build`, a tool that parallelizes Nix attribute evaluation, which dramatically reduces build time for large derivations, or when building multiple derivations. By default, it builds whatever attributes are defined in the `checks` output of the flake; in our case, both package variants. The Cachix integration is configured to push artifacts to a binary cache, so that previously built derivations can be shared across CI runs. Additionally, the `--skip-cached` flag ensures that we don't download any packages which already exist in the binary cache.

Finally we have the release and upload phases. First, the packages built by `nix-fast-build` are uploaded as artifacts for a draft GitHub release, allowing for manual verification before going live. Then, the upload step synchronizes those artifacts to Cloudflare R2 storage. It does this by calling the `upload` app, which runs a python script that uses `boto3` to upload the files through the S3 API. The flake app is configured to read environment variables from the `.env` file, so we recreate it using the repositories secret variables.
-->


---
transition: fade-out
---

# Results & Impact

The project's success was measured by the reduction in user effort and the introduction of a reliable, automated release process.

| Metric                  | Before (Manual Process)                                | After (My Automated System)                               | Impact                                    |
| ----------------------- | ------------------------------------------------------ | --------------------------------------------------------- | ----------------------------------------- |
| **Install Time**        | 2-4 hours of research, downloads, and manual commands. | `~8 minutes` for a single command.                        | **~93-96% reduction** in user time-to-OS. |
| **Install Success Rate**| Highly variable, prone to user error.                  | High, deterministic, and reproducible.                    | Drastic increase in reliability.          |
| **Reproducibility**     | Zero. Every install was unique.                        | **100% reproducible** builds via Nix.                     | Guaranteed consistency.                   |

<!--
The impact of this work was can be quantified it in several ways.

For the end-user, what was previously a multi-hour task with a high chance of failure became a simple, 8-minute one-liner.

For the topic of "NixOS on Apple Silicon" itself, it went from having no hosted installation method to a fully automated release and distribution system. You simply run a script (exposed as a Nix flake app) to bump the version and pushes a tag. About an hour later, the artifacts (both `ext4` and `btrfs` images) are live on the CDN.
-->

---
transition: fade-out
---

# Takeaways

What I learned from this project.

<v-clicks>

- **Complex Problems Require Simple Solutions:** Use existing, simple tools in a coordinated way to solve complex problems. Nix's declarative nature allowed me to compose these tools into a reliable pipeline.

- **End-to-End Thinking:** The core technology (an installer package) was only 50% of the solution. The packaging, distribution, and installer-facing metadata were just as critical. A reliable deployment and distribution strategy is an equal part of the product.

- **Design and Build Robust Automation:** By automating the release process, it not only saves time but also enforces consistency and quality. This declarative, automated approach is the only way to build complex system deployments reliably.

- **Nix is a Powerful Tool for System Integration:** Nix's ability to create hermetic builds and its powerful package management capabilities were key enablers. It allowed us to build complex system images in a reproducible way, abstracted from the host environment.

</v-clicks>

<!--
These are the key engineering insights I took away from this project.

The first takeaway is about breaking large problems down into simpler steps. I composed existing tools - fdisk, awk, 7zip, QEMU - into a reliable pipeline to handle a multifaceted challenge. Nix's declarative model was the perfect for this.

The second point speaks to holistic engineering. The technical challenge of building the disk image was only half of the solution. The other half was making it accessible through proper packaging, reliable distribution via CDN, and seamless integration with the existing Asahi installer ecosystem.

Third, automation is essential for consistency. By using Infrastructure-as-Nix-Code, I minimized human error and created a system that enforces consistency.

Finally, this project demonstrated Nix's unique strengths in system integration work. The ability to create hermetic, reproducible builds while orchestrating complex multi-stage processes across different environments, all from a single flake.
-->

---
transition: fade-out
---

# Why Me?

<v-clicks>

- **Solve Complex Systems Integration Problems:** I successfully bridged a gap between NixOS and the asahi-installer by reasoning from first principles.

* **Design and Build Robust Automation:** I engineered a CI/CD pipeline that promises reliability and efficiency.

- **Versatility:** My work spanned low-level system operations, to declarative NixOS configuration, to high-level cloud deployment and content delivery.

* **Understanding Core Concepts of Declarative Programming**: I have a deep understanding of Nix's declarative model and functional programming, and this project shows my ability to build complex systems in a reproducible way.

I truly am passionate about solving these kinds of deep, technical challenges, and I am confident that my skills in system architecture, automation, and problem-solving would allow me to make meaningful contributions at Neuralink.

**Thank you.**

</v-clicks>

<!--
To summarize, this project is a microcosm of how I approach engineering. I start with a difficult user problem, break it down into its fundamental technical challenges, and build a holistic and reliable solution that doesn't cut corners.

I've shown my ability to work across different technology stacks, from low level system APIs, to declarative programming, to cloud-based CI/CD pipelines. I believe I have what's needed to help solve the incredible challenges you are solving at Neuralink.

Thank you for your time!
-->
