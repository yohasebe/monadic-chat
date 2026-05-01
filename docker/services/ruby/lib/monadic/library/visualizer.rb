# frozen_string_literal: true

require 'json'
require 'open3'
require 'securerandom'
require 'time'

require_relative 'store'
require_relative '../utils/environment'

module Monadic
  module Library
    # Renders Level T (trajectory) embeddings as 2D PCA plots. Hands the
    # heavy lifting (numpy, matplotlib, plotly) off to a Python script
    # that runs in the python container; this Ruby module is a thin
    # orchestrator that fetches points from Qdrant, writes them as JSON
    # under the shared volume, invokes the script via `docker exec`, and
    # returns the generated PNG / HTML paths.
    module Visualizer
      module_function

      PYTHON_CONTAINER = 'monadic-chat-python-container'
      PYTHON_SCRIPT = '/monadic/scripts/utilities/library_trajectory_plot.py'
      DEFAULT_OUTPUT_DIR = '/monadic/data/library/trajectories'

      # Plot a single conversation's discourse trajectory.
      # Returns { png_path:, html_path:, points: } using host-visible paths.
      def plot_trajectory(store:, conversation_id:, title: nil)
        points = fetch_trajectory_points(store, conversation_id)
        raise ArgumentError, "No trajectory data for #{conversation_id}" if points.empty?

        spec = {
          'title' => title || "Discourse Trajectory — #{conversation_id}",
          'conversations' => [
            {
              'conversation_id' => conversation_id,
              'label' => title || conversation_id,
              'points' => points
            }
          ]
        }
        render_via_python(spec, label: conversation_id)
      end

      # Plot multiple conversations' trajectories in a shared PCA space.
      # Useful for cross-corpus comparison and side-by-side discourse
      # analysis across conversations.
      def plot_cross_corpus(store:, conversation_ids:, labels: {}, title: nil)
        raise ArgumentError, 'conversation_ids must be a non-empty array' unless conversation_ids.is_a?(Array) && !conversation_ids.empty?

        conversations = conversation_ids.map do |cid|
          pts = fetch_trajectory_points(store, cid)
          raise ArgumentError, "No trajectory data for #{cid}" if pts.empty?
          {
            'conversation_id' => cid,
            'label' => labels[cid] || labels[cid.to_s] || cid,
            'points' => pts
          }
        end

        spec = {
          'title' => title || "Cross-Corpus Discourse Trajectory (#{conversation_ids.size} conversations)",
          'conversations' => conversations
        }
        render_via_python(spec, label: "cross-corpus-#{conversation_ids.size}")
      end

      # ─── Internals ─────────────────────────────────────────────────────

      def fetch_trajectory_points(store, conversation_id)
        out = []
        cursor = nil
        loop do
          page = store.scroll(
            collection: VectorStore::Schema::LIBRARY_TRAJECTORY,
            filter: store.combine_filters(
              store.visibility_filter(:kb),
              store.conversation_filter(conversation_id)
            ),
            limit: 256,
            offset: cursor,
            with_vectors: true
          )
          page[:points].each do |p|
            vector = p.dig('vector', 'content') || []
            payload = p['payload'] || {}
            out << {
              'vector' => vector,
              'turn_idx' => payload['turn_idx'].to_i
            }
          end
          break if page[:next].nil?
          cursor = page[:next]
        end
        out
      end

      def render_via_python(spec, label:)
        input_path_host, input_path_container = stage_input(spec, label)
        stdout, status = run_python_script(input_path_container)
        raise "library_trajectory_plot.py exited with #{status.exitstatus}: #{stdout[0, 500]}" unless status.success?
        result = JSON.parse(stdout.lines.last.to_s)
        raise "Plot generation failed: #{result['error']}" if result['error']

        # The Python script writes container-side paths (e.g., /monadic/data/...).
        # Translate them to host-visible paths so Ruby callers can serve files.
        {
          png_path: container_path_to_host(result['png_path']),
          html_path: container_path_to_host(result['html_path']),
          points: result['conversations']&.first&.dig('points'),
          input_path: input_path_host
        }
      end

      def stage_input(spec, label)
        host_dir = File.join(Monadic::Utils::Environment.shared_volume, 'library', 'inputs')
        FileUtils.mkdir_p(host_dir)
        filename = "trajectory_input_#{label}_#{Time.now.to_i}_#{SecureRandom.hex(4)}.json"
        host_path = File.join(host_dir, filename)
        File.write(host_path, JSON.pretty_generate(spec))

        container_path = host_path_to_container(host_path)
        [host_path, container_path]
      end

      def run_python_script(input_path_container)
        cmd = [
          'docker', 'exec', PYTHON_CONTAINER,
          'python', PYTHON_SCRIPT,
          '--input', input_path_container,
          '--output-dir', DEFAULT_OUTPUT_DIR
        ]
        Open3.capture2e(*cmd)
      end

      def host_path_to_container(path)
        host_root = Monadic::Utils::Environment.shared_volume
        return path unless path.start_with?(host_root)
        path.sub(host_root, '/monadic/data')
      end

      def container_path_to_host(path)
        return path if path.nil?
        host_root = Monadic::Utils::Environment.shared_volume
        return path unless path.start_with?('/monadic/data')
        path.sub('/monadic/data', host_root)
      end
    end
  end
end
