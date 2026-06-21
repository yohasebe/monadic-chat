# frozen_string_literal: true

# Helper methods for Workflow Viewer graph data extraction.
# Extracted from monadic.rb for testability.

module Monadic
  module Utils
    module WorkflowViewerHelpers
      module_function

      def wv_extract_tools(s)
        pt = s[:progressive_tools] || s["progressive_tools"] || {}
        all_names = pt[:all_tool_names] || pt["all_tool_names"] || []
        always_visible = pt[:always_visible] || pt["always_visible"] || []
        conditional = pt[:conditional] || pt["conditional"] || []
        conditional_map = conditional.each_with_object({}) do |c, h|
          name = c[:name] || c["name"]
          h[name] = {
            visibility: (c[:visibility] || c["visibility"]).to_s,
            unlock_hint: c[:unlock_hint] || c["unlock_hint"]
          }
        end

        all_names.map do |name|
          meta = conditional_map[name]
          {
            name: name,
            visibility: meta ? meta[:visibility] : "always",
            unlock_hint: meta ? meta[:unlock_hint] : nil
          }
        end
      end

      def wv_extract_shared_tool_groups(s)
        groups = s[:imported_tool_groups] || s["imported_tool_groups"] || []
        groups.map do |g|
          group_name = (g[:name] || g["name"]).to_sym
          tool_names = begin
            MonadicSharedTools::Registry.tools_for(group_name).map(&:name)
          rescue ArgumentError
            []
          end
          {
            name: group_name.to_s,
            visibility: (g[:visibility] || g["visibility"]).to_s,
            tool_count: g[:tool_count] || g["tool_count"] || tool_names.size,
            tool_names: tool_names
          }
        end
      end

      def wv_extract_agents(s)
        agents = s[:agents] || s["agents"] || {}
        agents.each_with_object({}) do |(k, v), h|
          h[k.to_s] = v.to_s
        end
      end

      # Raw image_generation setting value (symbol or string key).
      def wv_image_generation_value(s)
        val = s[:image_generation]
        val = s["image_generation"] if val.nil?
        val
      end

      # True only when the app actually GENERATES images.
      # "upload_only"/"disabled"/false enable image input (or nothing), not
      # generation. This mirrors the frontend `toBool()` in
      # public/js/monadic/model-capabilities.js so the Workflow Viewer agrees
      # with the rest of the UI about what counts as an image-generating app.
      def wv_generates_image?(s)
        val = wv_image_generation_value(s)
        val == true || val == "true"
      end

      # True when the app accepts image uploads as input (image-to-X) without
      # generating images itself (e.g. Music/Video Generator's image-to-music
      # / image-to-video).
      def wv_accepts_image_upload?(s)
        wv_image_generation_value(s) == "upload_only"
      end

      def wv_extract_features(s)
        flags = %w[websearch monadic image pdf jupyter mermaid math abc
                   easy_submit auto_speech initiate_from_assistant]
        result = flags.each_with_object({}) do |f, h|
          val = s[f.to_sym]
          val = s[f] if val.nil?
          h[f] = !!val
        end
        # image_generation only counts when the app truly generates images;
        # "upload_only" is image input, not a generation feature.
        result["image_generation"] = wv_generates_image?(s)
        # video_generation is a generation feature in its own right.
        result["video_generation"] = !!(s[:video_generation] || s["video_generation"])
        # Normalize: pdf_vector_storage and pdf_upload imply pdf capability
        unless result["pdf"]
          result["pdf"] = !!(s[:pdf_vector_storage] || s["pdf_vector_storage"] || s[:pdf_upload] || s["pdf_upload"])
        end
        result
      end
    end
  end
end
