#!/bin/bash
set -e

cd "$(dirname "$0")"

VERSION="0.1.0"

echo "Releasing squirreldb-sdk v${VERSION}..."

echo "Installing dependencies..."
bundle install --quiet

echo "Running tests..."
bundle exec rake test

echo "Building gem..."
gem build squirreldb-sdk.gemspec

echo "Publishing to RubyGems..."
gem push squirreldb-sdk-${VERSION}.gem

echo "Cleaning up..."
rm -f squirreldb-sdk-${VERSION}.gem

echo "Released squirreldb-sdk@${VERSION}"
echo ""
echo "Users can install with:"
echo "  gem install squirreldb-sdk"
