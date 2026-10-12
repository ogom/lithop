# frozen_string_literal: true

require_relative "release_check"

namespace :release do
  desc "Validate and smoke-test the release gem without publishing it"
  task check: %i[spec rubocop] do
    sh "bundle exec rbs validate"
    sh "gem build lithop.gemspec"
    Lithop::ReleaseCheck.call
  end
end
