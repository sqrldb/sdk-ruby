# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "tests"
  t.libs << "lib"
  t.test_files = FileList["tests/**/*_test.rb"]
end

task default: :test
