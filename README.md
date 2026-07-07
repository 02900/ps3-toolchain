# ps3-toolchain

A ready-to-use **PS3 homebrew cross-compiler toolchain** packaged as a Docker image, so
you can build PS3 homebrew on **macOS, Windows, or Linux** without installing the toolchain
on your machine.

## Images: a core + one image per renderer

The **core** image is the base every PS3 homebrew build starts from; the **renderer** stacks
are separate variants built `FROM` it, so a renderer never drags another's libraries. Pick the
image that matches how you draw:

| Image | = | Adds | Use it for |
|---|---|---|---|
| **`ps3-toolchain`** (core) | Ubuntu 20.04 + [ps3toolchain](https://github.com/ps3dev/ps3toolchain) (`powerpc64-ps3-elf-gcc`) + [PSL1GHT](https://github.com/ps3dev/PSL1GHT) + render-agnostic portlibs (zlib/freetype/libpng, MikMod, PolarSSL, libcurl, Mini18n) | — | render-agnostic code, or as the base for a variant |
| **`ps3-toolchain-tiny3d`** | core + | Tiny3D, YA2D, font3d | Tiny3D / ya2d homebrew |
| **`ps3-toolchain-rsxgl`** | core + | RSXGL (OpenGL 3.1 over the RSX) | raw OpenGL homebrew |
| **`ps3-toolchain-raylib`** | rsxgl + | raylib | raylib homebrew |

```
ps3-toolchain (core)
├─ ps3-toolchain-tiny3d   (Dockerfile.tiny3d)
├─ ps3-toolchain-rsxgl    (Dockerfile.rsxgl)
└─ ps3-toolchain-raylib   (Dockerfile.raylib, FROM rsxgl)
```

Each [`Dockerfile*`](.) builds by **cloning/downloading from upstream at build time** — no
third-party source is committed here. A per-variant CI workflow publishes each image to GHCR
(rebuilt only when its Dockerfile changes; `workflow_dispatch` re-triggers after a core change).
A private, fully-vendored (offline) variant of the core lives in `02900/ps3-toolchain-vendored`.

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
> the PS3). It does not run PS3 programs — load the resulting `.self` onto the console with
> `ps3load` (also bundled in the image, see below).

### Send a build to the PS3

The image also ships `ps3load`, so you can push a build to a console running a network
loader (PS3LoadX, listening on port `4299`) without installing anything locally. The key
flag is **`--network host`**: it lets the container reach your PS3 directly on the LAN.
Without it Docker's NAT delivers the file but the loader **never launches it** (the app
just sits there).

```bash
docker run --rm --network host \
  -e PS3LOAD=tcp:192.168.X.X \
  -v "$PWD":/src -w /src \
  ghcr.io/02900/ps3-toolchain \
  ps3load /src/<your-build>.self
```

Replace `192.168.X.X` with your PS3's IP. On Apple Silicon, add `--platform linux/amd64`.

### Platform notes

- **macOS (Apple Silicon):** the image is `linux/amd64`; add `--platform linux/amd64` to
  `docker run`/`docker build` (runs under emulation).
- **Windows:** use WSL2 and the commands above, or PowerShell with `-v ${PWD}:/src`.
- **Linux:** if your user isn't in the `docker` group, prefix the commands with `sudo`.

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
