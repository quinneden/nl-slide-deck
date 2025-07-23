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
Hi everyone, my name is Quinn Edenfield. Thank you for this opportunity. Today, I'm going to walk you through a project that showcases my approach to solving complex system integration and automation challenges. We'll go from a Git repository to a fully automated, one-command installer that deploys a custom NixOS environment onto bare-metal Apple Silicon hardware.
-->

---
transition: fade-out
---

# The Problem

Installing NixOS on an Apple Silicon Mac was a complex, expert-only process involving manual partitioning and hours of debugging.


<div v-click="1">

**The Core Technical Challenge:** How do you programmatically build a bootable, custom NixOS disk image and package it for a third-party installer (`asahi-installer`) that expects a specific package format, all within a fully automated CI/CD pipeline?

</div>

<div v-click="2">

This breaks down into three sub-problems:

</div>

<div v-click="3">

<div v-motion
  :initial="{ opacity: 0 }"
  :click-3="{ opacity: 1, transition: { delay: 200, duration: 800 } }">

1. **Declarative Image Generation:** How to create a raw, bootable `aarch64-linux` disk image in a reproducible way?

</div>

<div v-motion
  :initial="{ opacity: 0 }"
  :click-3="{ opacity: 1, transition: { delay: 1000, duration: 800 } }">

2. **Format Transformation:** How to deconstruct this image into the specific file/directory structure required by the installer?

</div>

<div v-motion
  :initial="{ opacity: 0 }"
  :click-3="{ opacity: 1, transition: { delay: 1800, duration: 800 } }">

3. **Automated Distribution:** How to automate the entire build, transformation, and release process to a public CDN on every version bump?

</div>

</div>

<!--
The goal was to make NixOS on Apple Silicon more accessible. But the technical hurdle was significant. I had two disconnected worlds: the world of NixOS, which is great at producing declarative, reproducible system configurations, and the world of the Asahi Installer, which is the only tool capable of safely partitioning a Mac's internal drive and blessing a new OS.

The installer doesn't just take an ISO or a disk image. It requires a specific set of files: a zipped archive of the root filesystem, a separate directory for the boot partition (ESP), and a JSON manifest file that describes the OS. My task was to bridge these two worlds and automate the entire process.
-->

---
transition: fade-out
---

# The Solution

I created a pipeline that transforms source Nix code into a NixOS package that users can install onto Apple Silicon hardware with minimal manual intervention.

<v-clicks>

1. **`nix run .#create-release`:** A Nix Flake app that pushes a version tag to the `main` branch.

2. **GitHub Actions:** That push triggers a CI/CD workflow.

3. **Nix Build:** The workflow uses `nix-fast-build` to concurrently evaluate, then build both NixOS package variants.

4. **Package & Transform:** Once the images are built, the next step deconstructs the `.img` file into a `.zip` archive and a JSON manifest.

5.  **Deploy:** The workflow uploads the final assets to a Cloudflare R2 bucket, which are then served, along with the installer bootstrap scripts, via `https://cdn.nixos-asahi.qeden.dev`.

6.  **User Install:** The user runs `curl -L https://nixos-asahi.qeden.dev/install | sh`, which executes the bootstrap script, subsequently fetching the installer and the metadata from the CDN to install the OS.

</v-clicks>

<!--
This is the high-level architecture of the project. It's a classic CI/CD pipeline, but the complexity is hidden in steps 3 and 4, which I'll go into later.

I adapted the logic from the similar image-builder script in the nixpkgs repository, with heavy modifications to support both ext4 and btrfs. I fully wrote the packaging logic, Nix functions in `lib`, and configured the GitHub Actions workflow and Python scripts for the final deployment to the cloud.

Let's zoom in on the most challenging part: building and packaging the image.
-->

---
transition: fade-out
layout: two-cols
layoutClass: gap-16
---

# Building

Building the `btrfs` and `ext4` Image Variants

<v-clicks>

**Challenge:** An environment capable of producing hermetic, deterministic builds was required, but creating the filesystems and partitioning the disk images required access to system-level resources, like virtual block devices.

**Solution:** A two-stage build process inside a QEMU virtual machine, orchestrated entirely by Nix.

This approach guarantees that the build is reproducible and independent of the host OS, by creating a hermetic Linux environment just for the filesystem-sensitive operations.

</v-clicks>

::right::

<div v-click="2" class="fade-in">

```nix
prepareStagingRoot = ''
  # Use nixos-install to populate a directory with the full NixOS closure
  # This allows us to later copy it into the disk image and set file
  # modification times deterministically.
  
  nixos-install \
    --root $PWD/root \
    --no-bootloader \
    --system ${config.system.build.toplevel}
'';
# ... truncated ...
buildImageStageOne = pkgs.vmTools.runInLinuxVM (
  pkgs.runCommand "stage-one" { ... } ''
    # Inside the VM, we have a block device (/dev/vda)
    mkfs.btrfs -L nixos /dev/vda2
    # Mount and create btrfs subvolumes for /, /nix, /home
    btrfs subvolume create /mnt/@
    # ... truncated ...
    # Copy the prepared rootfs into the newly formatted filesystem
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
Here's where I apply first principles. The problem: I need to create a bootable disk image with a specific filesystem layout, but I can't just run `mkfs.btrfs` or `mkfs.ext4` on the host machine. The Nix build environment is sandboxed and doesn't allow mounting filesystems or accessing block devices directly. The tooling for `ext4` allows for specifying the offset of the partition, but `btrfs` doesn't. This means we need access to virtual block devices to mount the partitions in order to create the filesystems.

First, outside the VM, I use `nixos-install` to populate a directory as a 'staging root' of the final operating system. This way we only need to run the command once for both image variants, and it allows us to set file modification times deterministically. This directory contains the full NixOS closure, which we will later copy into the disk image.

Second, a QEMU virtual machine is booted. Nix handles the magic of spinning up the VM and passing in the staging root and disk image. Inside this hermetic Linux environment, the filesystems are created, then the staging root is copied into the newly formatted root filesystems.
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

This derivation is a micro-factory: it takes in a disk image and outputs a zip file and a JSON file, using a precise chain of standard tools to perform a highly specific transformation.

</v-clicks>

::right::

<div v-click="3" class="fade-in" style="transform: scale(0.9);">

```nix
stdenv.mkDerivation {
  # ... truncated ...
  nativeBuildInputs = [ gawk jq p7zip util-linux ];

  buildPhase = ''
    diskImage="${image.name}.img"

    # Use fdisk + awk to parse the partition table of the .img file
    # This extracts the start/end sectors of each partition.
    eval "$(
      fdisk -Lnever -lu -b 512 "$diskImage" |
      awk "/^$diskImage/ { printf \"dd if=$diskImage of=%s skip=%s count=%s bs=512\\n\", \$1, \$2, \$4 }"
    )"

    # This created two new image: ESP and rootfs
    # Now, extract the ESP contents and rename the rootfs partition.
    7z x -o"package/esp" "''${diskImage}1"
    mv "''${diskImage}2" package/root.img

    # 3. Create the final zip archive from the `package` directory.
    7z a -tzip -r ../"$pkgZip" ./package

    # 4. Generate the JSON manifest using data passed from the image build.
    jq -r <<< ${lib.escapeShellArg installerData} > "$installerData"
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
So we have our `nixos.img` file. But we can't ship it. It has to be torn apart again, but in a very controlled and reproducible way.

Inside another Nix derivation, a sequence of low-level tools is used to do this. Nix build environments are sandboxed and don't allow mounting.

First, it uses `fdisk` and `awk` to parse the image's partition table. The `awk` script dynamically generates `dd` commands to carve out each partition into its own separate file.

Next, it uses `7zip` to extract the contents of the boot partition file. For the root filesystem partition, the file is renamed to `root.img` as required by the installer.

Finally, it zips up the results and used `jq` to generate the final JSON manifest (which is generated by more Nix logic in `lib/generate-installer-data.nix`). Since this is a Nix derivation, the entire chain is deterministic.
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
