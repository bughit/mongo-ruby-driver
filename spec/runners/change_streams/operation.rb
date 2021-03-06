# Copyright (C) 2014-2020 MongoDB Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Mongo
  module ChangeStreams
    class Operation

      # The operation name.
      #
      # @return [ String ] name The operation name.
      #
      # @since 2.6.0
      attr_reader :name

      # Instantiate the operation.
      #
      # @return [ Hash ] spec The operation spec.
      #
      # @since 2.6.0
      def initialize(spec)
        @spec = spec
        @name = spec['name']
      end

      def execute(db1, db2)
        db = case @spec['database']
             when db1.name
               db1
             when db2.name
               db2
             end

        send(Utils.underscore(@spec['name']) ,db[@spec['collection']])
      end

      private

      def insert_one(coll)
        coll.insert_one(document)
      end

      def update_one(coll)
        coll.update_one(filter, arguments['update'])
      end

      def replace_one(coll)
        coll.replace_one(filter, arguments['replacement'])
      end

      def delete_one(coll)
        coll.delete_one(filter)
      end

      def drop(coll)
        coll.drop
      end

      def rename(coll)
        coll.client.use(:admin).command({
          renameCollection: "#{coll.database.name}.#{coll.name}", 
          to: "#{coll.database.name}.#{arguments['to']}"
        })
      end

      def arguments
        @spec['arguments']
      end

      def document
        arguments['document']
      end

      def filter
        arguments['filter']
      end
    end
  end
end