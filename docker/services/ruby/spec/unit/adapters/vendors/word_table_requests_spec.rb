# frozen_string_literal: true

require 'spec_helper'

helpers = Dir[File.expand_path('../../../../lib/monadic/adapters/vendors/*_helper.rb', __dir__)]
helpers.each { |file| require file }

# Each request a vendor's helper makes to its model is a request of the
# chat's word table: the reply and the tools it calls are read with the
# snapshot the request was hidden with.
RSpec.describe 'The requests of the vendor helpers' do
  it 'are each a request of the word table' do
    names = helpers.filter_map { |file| File.read(file)[/^module (\w+Helper)\b/, 1] }
                   .select { |name| Object.const_get(name).method_defined?(:api_request) }
    expect(names.size).to be >= 8
    names.each do |name|
      expect(Object.const_get(name).ancestors.first).to eq(Monadic::Utils::Privacy::Words::Requests), name
    end
  end
end
