# This dockerfile is taken from
# https://soap.coffee/~lthms/posts/DreamWebsite.html

# This stage builds an environment for compiling the website
FROM alpine:3.21 AS build_environment

# Use alpine /bin/ash and set shell options
# See https://docs.docker.com/build/building/best-practices/#using-pipes
SHELL ["/bin/ash", "-euo", "pipefail", "-c"]

USER root
WORKDIR /root

## Probably some of those dependencies are not necessary
RUN apk add autoconf automake bash build-base ca-certificates opam gcc \ 
  git rsync gmp-dev libev-dev openssl-libs-static pkgconf zlib-static \
  openssl-dev zlib-dev

RUN opam init --bare --yes --disable-sandboxing
COPY dune-project .

# This is necessary to build a static binary
# https://soap.coffee/~lthms/posts/OCamlStaticBinaries.html
RUN opam switch create . --packages "ocaml-option-static,ocaml-option-no-compression,ocaml.5.2.0"
RUN eval $(opam env)

# Here are the OCaml dependencies of the website
RUN opam install --yes dune crunch tezt dream dream-html

# This stage builds the website
FROM build_environment AS builder

COPY bin ./bin
COPY assets ./assets
RUN eval $(opam env) && dune build bin/main.exe --profile=static

# This stage builds a docker image containing only the website binary
FROM alpine:3.21 AS website

COPY --from=builder /root/_build/default/bin/main.exe /bin/main.exe

# The website runs on port 8080
EXPOSE 8080

ENTRYPOINT "/bin/main.exe"

