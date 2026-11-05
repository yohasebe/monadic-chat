# frozen_string_literal: true

require_relative "../spec_helper"

# A unit example never reaches the state folder of the computer running the
# specs: spec_helper gives the run a state folder of its own.
RSpec.describe "the state folder in unit specs" do
  it "is a folder of the run's own, and the history is kept there" do
    home_state = File.join(Dir.home, "monadic", "state")
    expect(Monadic::Utils::Environment.state_path).not_to eq(home_state)
    expect(File.directory?(Monadic::Utils::Environment.state_path)).to be(true)
    expect(Monadic::History::Store.default.path).to start_with(Monadic::Utils::Environment.state_path)
  end
end
