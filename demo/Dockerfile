# OddSockets Ruby SDK - two-client round-trip demo
#
# Build from the repo ROOT so the SDK source is in context (the demo uses a
# Bundler path dependency - gem 'oddsockets', path: '..' - to compile the SDK
# straight from the parent, without publishing anything):
#
#   docker build -f demo/Dockerfile -t oddsockets-ruby-demo .
#   docker run --rm -e ODDSOCKETS_API_KEY="ak_your_key_here" oddsockets-ruby-demo
#
# A successful run prints "OK - cross-client round-trip verified" and exits 0.

FROM ruby:3.3-slim

# git is needed by the gemspec (files are enumerated via `git ls-files`);
# build-essential covers any native gem extensions.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /sdk
COPY . /sdk

WORKDIR /sdk/demo
RUN bundle install

CMD ["bundle", "exec", "ruby", "demo.rb"]
