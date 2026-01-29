#!/bin/bash
set -e

cd "$(dirname "$0")"

VERSION=$(grep 'spec.version' squirreldb.gemspec | awk -F'"' '{print $2}')

echo "Building squirreldb Ruby SDK v${VERSION}..."

rm -f squirreldb-*.gem

gem build squirreldb.gemspec

echo "Running tests..."
bundle exec rake test

echo "Publishing to RubyGems..."
gem push squirreldb-${VERSION}.gem

echo "Published squirreldb-${VERSION} to RubyGems"
