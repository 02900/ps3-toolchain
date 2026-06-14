# ps3-toolchain

A ready-to-use **PS3 homebrew cross-compiler toolchain** packaged as a Docker image, so
you can build PS3 homebrew on **macOS, Windows, or Linux** without installing the toolchain
on your machine.

The image contains Ubuntu 20.04 plus:

- the [ps3toolchain](https://github.com/ps3dev/ps3toolchain) cross compiler
  (`powerpc64-ps3-elf-gcc`) and the [PSL1GHT](https://github.com/ps3dev/PSL1GHT) SDK,
- the common portlibs: **Tiny3D, YA2D, PolarSSL, libcurl, MikMod, Mini18n** (plus
  freetype/zlib/jpgdec/pngdec from ps3libraries).

The [`Dockerfile`](Dockerfile) builds everything by **cloning/downloading from upstream at
build time** — no third-party source is committed here. A private, fully-vendored
(offline, upstream-independent) variant lives in `02900/ps3-toolchain-vendored`.

---

## Use it to compile PS3 homebrew

Mount your project at `/src` and run its build. The cross-compiled `.self`/`.elf` files
appear in your working tree.

```bash
docker run --rm -v "$PWD":/src -w /src ghcr.io/02900/ps3-toolchain make
```

Interactive shell in the toolchain environment:

```bash
docker run --rm -it -v "$PWD":/src -w /src ghcr.io/02900/ps3-toolchain bash
```

> The image only **compiles** homebrew (it runs on your PC and emits PowerPC binaries for
> the PS3). It does not run PS3 programs — load the resulting `.self` with `ps3load`.

### Platform notes

- **macOS (Apple Silicon):** the image is `linux/amd64`; add `--platform linux/amd64` to
  `docker run`/`docker build` (runs under emulation).
- **Windows:** use WSL2 and the commands above, or PowerShell with `-v ${PWD}:/src`.

---

## Get the image

Pull the prebuilt image (published by CI):

```bash
docker pull ghcr.io/02900/ps3-toolchain:latest
```

Or build it yourself:

```bash
docker build -t ps3-toolchain .
```

The first build is slow (~30 min — it compiles GCC, newlib, etc.); afterwards Docker
caches it. CI rebuilds the image only when the `Dockerfile` changes.

---

## Versions

Pinned in the `Dockerfile` / ps3toolchain: GCC 7.2.0, binutils 2.22, newlib 1.20.0,
PolarSSL 1.3.9, libcurl 7.64.1, MikMod 3.1.11, on an Ubuntu 20.04 host (whose GCC-9 can
build the old GCC; newer hosts cannot).

## Notice

This image builds and bundles third-party software (GCC, PSL1GHT, the portlibs, etc.),
each under its own license. It is provided as a build convenience; the respective upstream
projects own their code.
