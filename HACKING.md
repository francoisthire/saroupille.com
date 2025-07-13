# Hacking this Website

This document describes how the repository is organized and how to build and modify the website. Everything is written in OCaml and can be compiled to a static binary or packaged in a small Docker image.

## Repository layout

- `bin/` – contains the OCaml sources for the website itself (`main.ml`).
- `assets/` – Markdown, HTML, CSS and JSON files used as content.
  `dune` rules in this directory run `ocaml-crunch` to embed these files
  directly into the binary.
- `deploy/` – an optional helper tool that automates deployment to Google
  Cloud Platform and Cloudflare.
- `Dockerfile` – builds the website in a minimal Alpine container.

The website uses [`dune`](https://dune.build) as its build system and
[`opam`](https://opam.ocaml.org/) for dependency management.

## Building locally

1. Install OCaml and `opam` (version 2.1 or newer).
2. Run `opam switch create . --packages ocaml.5.2.0` to create a local
   switch and install dependencies.
3. Build the site with:

   ```bash
   dune build
   ```

4. Run the development server:

   ```bash
   dune exec bin/main.exe
   ```

The server listens on port `8080`. Browse to `http://localhost:8080` to
view the site.

For a fully static binary you can use the `static` profile:

```bash
dune build --profile=static
```

## Docker image

A Dockerfile is provided to build and run the website inside a container:

```bash
docker build -t website .
docker run --rm -p 8080:8080 website
```

## Deployment helper

The `deploy` directory contains a small CLI, built with Tezt, that
interacts with GCP and Cloudflare.  The tool can create a VM, push the
docker image and configure firewall rules.  See `deploy/README.md` for a
step‑by‑step guide.

A typical deployment looks like:

```bash
dune exec deploy/main.exe -- gcloud create vm -v
```

## Customizing the site

All content lives under the `assets` directory.  Editing the JSON or
Markdown files there and rebuilding is enough to change the pages.  The
OCaml code in `bin/main.ml` reads these files at compile time, so running
`dune build` after any modification is required.

Feel free to fork the repository and adapt it to your needs.  Pull
requests and issues are welcome!

