ARG RUBY_VERSION
FROM ruby:${RUBY_VERSION}
ARG APT_PACKAGES=""
# The base image already has build tools and the pg/mysql/sqlite/yaml headers.
# Added: a JS runtime + yarn (Rails <= 6 asset pipelines), DB clients (dbconsole, structure.sql), libvips.
RUN apt-get update \
 && apt-get install -y --no-install-recommends nodejs npm postgresql-client default-mysql-client libvips-tools ${APT_PACKAGES} \
 && npm install -g yarn \
 && rm -rf /var/lib/apt/lists/*
