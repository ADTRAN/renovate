# Base image
#============
FROM renovate/yarn:1.21.1@sha256:6aeeab4a40e4687a961ab8bcefb2fa4ce374c4f0324cc40d37fbcecbfac4af0c AS base

LABEL maintainer="Rhys Arkins <rhys@arkins.net>"
LABEL name="renovate"
LABEL org.opencontainers.image.source="https://github.com/renovatebot/renovate"


# required for install
USER root


# Build image
#============
FROM base as tsbuild

# Python 3 and make are required to build node-re2
RUN apt-get update && apt-get install -y python3-minimal build-essential

COPY package.json .
COPY yarn.lock .
RUN yarn install --frozen-lockfile

COPY lib lib
COPY tsconfig.json tsconfig.json
COPY tsconfig.app.json tsconfig.app.json

RUN yarn build:docker

# Prune node_modules to production-only so they can be copied into the final image
RUN yarn install --production --frozen-lockfile


# Final image
#============
FROM base as final

RUN apt-get update && apt-get install -y gpg curl wget unzip xz-utils git openssh-client && \
    rm -rf /var/lib/apt/lists/*

## Gradle

RUN apt-get update && apt-get install -y --no-install-recommends openjdk-8-jre-headless gradle && \
    rm -rf /var/lib/apt/lists/*

# Erlang

RUN cd /tmp && \
    curl https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb -o erlang-solutions_1.0_all.deb && \
    dpkg -i erlang-solutions_1.0_all.deb && \
    rm -f erlang-solutions_1.0_all.deb

ENV ERLANG_VERSION=22.0.2-1

RUN apt-get update && \
    apt-cache policy esl-erlang && \
    apt-get install -y esl-erlang=1:$ERLANG_VERSION && \
    rm -rf /var/lib/apt/lists/*

# Elixir

ENV ELIXIR_VERSION 1.8.2

RUN curl -L https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/Precompiled.zip -o Precompiled.zip && \
    mkdir -p /opt/elixir-${ELIXIR_VERSION}/ && \
    unzip Precompiled.zip -d /opt/elixir-${ELIXIR_VERSION}/ && \
    rm Precompiled.zip

ENV PATH $PATH:/opt/elixir-${ELIXIR_VERSION}/bin

# PHP Composer

RUN apt-get update && apt-get install -y php-cli php-mbstring && \
    rm -rf /var/lib/apt/lists/*

ENV COMPOSER_VERSION=1.8.6

RUN php -r "copy('https://github.com/composer/composer/releases/download/$COMPOSER_VERSION/composer.phar', '/usr/local/bin/composer');"

RUN chmod +x /usr/local/bin/composer

# Go Modules

RUN apt-get update && apt-get install -y bzr mercurial && \
    rm -rf /var/lib/apt/lists/*

ENV GOLANG_VERSION 1.13.4

# Disable GOPROXY and GOSUMDB until we offer a solid solution to configure
# private repositories.
ENV GOPROXY=direct GOSUMDB=off

RUN wget -q -O go.tgz "https://golang.org/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz" && \
  tar -C /usr/local -xzf go.tgz && \
  rm go.tgz && \
  export PATH="/usr/local/go/bin:$PATH"

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

ENV CGO_ENABLED=0

# Python

RUN apt-get update && apt-get install -y python3.8-dev python3.8-venv python3-distutils && \
    rm -rf /var/lib/apt/lists/*

RUN rm -fr /usr/bin/python3 && ln /usr/bin/python3.8 /usr/bin/python3
RUN rm -rf /usr/bin/python && ln /usr/bin/python3.8 /usr/bin/python

# Pip

RUN curl --silent https://bootstrap.pypa.io/get-pip.py | python

# Docker client and group

RUN groupadd -g 999 docker
RUN usermod -aG docker ubuntu

ENV DOCKER_VERSION=19.03.1

RUN curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz \
  && tar xzvf docker-${DOCKER_VERSION}.tgz --strip 1 \
  -C /usr/local/bin docker/docker \
  && rm docker-${DOCKER_VERSION}.tgz

USER ubuntu

# HOME does not get passed after user switch :-(
ENV HOME=/home/ubuntu

# Cargo

ENV RUST_BACKTRACE=1 \
  PATH=${HOME}/.cargo/bin:$PATH

ENV RUST_VERSION=1.36.0

RUN set -ex ;\
  curl https://sh.rustup.rs -sSf | sh -s -- --no-modify-path --profile minimal --default-toolchain ${RUST_VERSION} -y

# Mix and Rebar

RUN mix local.hex --force
RUN mix local.rebar --force

# Pipenv

ENV PATH="${HOME}/.local/bin:$PATH"

RUN pip install --user pipenv

# Poetry

ENV POETRY_VERSION=1.0.0

RUN curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python - --version ${POETRY_VERSION}

ENV PATH="${HOME}/.poetry/bin:$PATH"
RUN poetry config virtualenvs.in-project false

# Renovate

COPY package.json .

COPY --from=tsbuild /usr/src/app/dist dist
COPY --from=tsbuild /usr/src/app/node_modules node_modules
COPY bin bin
COPY data data


# Numeric user ID for the ubuntu user. Used to indicate a non-root user to OpenShift
USER 1000

ENTRYPOINT ["node", "/usr/src/app/dist/renovate.js"]
CMD []
