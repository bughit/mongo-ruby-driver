#!/bin/bash

set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail

. `dirname "$0"`/functions.sh

arch=`host_arch`

show_local_instructions

set_env_vars
setup_ruby

export BUNDLE_GEMFILE=gemfiles/mongo_kerberos.gemfile
bundle_install

bundle exec rspec \
  spec/spec_tests/uri_options_spec.rb \
  spec/spec_tests/connection_string_spec.rb \
  spec/mongo/uri/srv_protocol_spec.rb \
  spec/mongo/uri_spec.rb \
  spec/integration/client_authentication_options_spec.rb
