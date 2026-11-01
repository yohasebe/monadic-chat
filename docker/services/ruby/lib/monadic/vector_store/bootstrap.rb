# frozen_string_literal: true

module Monadic
  module VectorStore
    # Creates the collections a store uses, with the payload indexes of the
    # schema. A collection made earlier gets the current schema's indexes;
    # that is tried once per process for each collection, whether it works
    # or not (creating an index that exists is not an error, and search works
    # without one). `indexed` and `mutex` hold that record for the caller.
    module Bootstrap
      module_function

      def ensure_collections!(store, names, indexed:, mutex:, tag:)
        names.each do |name|
          defn = Schema::DEFINITIONS[name]
          if store.collection_exists?(name: name)
            ensure_indexes(store, name, defn, indexed: indexed, mutex: mutex, tag: tag)
          else
            store.create_collection(name: name, vectors: defn[:vectors], payload_indexes: defn[:payload_indexes])
            mutex.synchronize { indexed[name] = true }
          end
        end
      end

      def ensure_indexes(store, name, defn, indexed:, mutex:, tag:)
        return if mutex.synchronize { indexed[name] }
        return unless store.respond_to?(:create_payload_index)

        mutex.synchronize { indexed[name] = true }
        Array(defn[:payload_indexes]).each do |idx|
          store.create_payload_index(name: name, field: idx[:field], schema: idx[:schema])
        end
      rescue BackendError, NotImplementedError => e
        Monadic::Utils::ExtraLogger.log { "[#{tag}] payload index for #{name} not created: #{e.message}" } if defined?(Monadic::Utils::ExtraLogger)
      end
    end
  end
end
