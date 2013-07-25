# Copyright (C) 2013 10gen Inc.
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
  # Client-side representation of a a server iterator (cursor)
  class Cursor

    MAX_QUERY_TRIES = 3

    def initialize(scope)
      @scope      = scope
      @cursor_id  = nil
      @collection = @scope.collection
      @client     = @collection.client
      @node       = nil
      @cache      = []
      @returned   = 0
    end

    def inspect
      "<Mongo::Cursor:0x#{object_id} @scope=#{@scope.inspect}>"
    end

    def each
      yield next_doc while cache
    end

    private

    def cache
      return true unless @cache.empty?
      return close if finished_requests?
      fetch_docs
    end

    def next_doc
      doc = @cache.shift
      check_err_doc(doc)
    end

    def close
      return nil unless @node
      return nil if closed?
      kill_cursors
    end

    def has_special_fields?
      @scope.query_opts.length > 0 ||
      !!sort                       ||
      !!hint                       ||
      !!comment                    ||
      needs_read_pref
    end

    def special_selector
      query =      { :$query => selector }
      query.merge!({ :$readPreference => read })
      query.merge!({ :$orderby => sort })              if sort
      query.merge!({ :$hint => hint })                 if hint
      query.merge!({ :$comment => comment })           if comment
      query.merge!({ :$snapshot => snapshot })         if snapshot
      query.merge!({ :$maxScan => max_scan })          if max_scan
      query.merge!({ :$showDiskLoc => show_disk_loc }) if show_disk_loc
      query
    end

    def fetch_docs
      return send_initial_query unless query_run?
      send_get_more
    end

    # @todo: Brandon: verify connecton interface
    def send_and_receive(connection, message)
      results, @node = connection.send_and_receive(MAX_QUERY_TRIES, message)
      @cursor_id     = results[:cursor_id]
      @returned      += results[:nreturned]
      @cache         += results[:docs]
    end

    def initial_query_message
      selector = has_special_fields? ? special_selector : selector
      Mongo::Protocol::Query.new(db_name, coll_name, selector, query_opts)
    end

    # @todo: Brandon: verify client interface
    def send_initial_query
      @client.with_node(read) do |connection|
        send_and_receive(connection, initial_query_message)
      end
    end

    def get_more_message
      Mongo::Protocol::GetMore.new(db_name, coll_name, to_return, @cursor_id)
    end

    # @todo: define exceptions
    def send_get_more
      raise Exception, 'No node set' unless @node
      @node.with_connection do |connection|
        send_and_receive(connection, get_more_message)
      end
    end

    def kill_cursors_message
      Mongo::Protocol::KillCursors.new([@cursor_id])
    end

    # @todo: Brandon: verify node interface
    def kill_cursors
      @node.with_connection do |connection|
        connection.send_message(kill_cursors_message)
      end
      @cursor_id = 0
      nil
    end

    def query_opts
      {
        :fields => @scope.fields,
        :skip => @scope.skip,
        :limit => to_return,
        :flags => flags,
      }
    end

    # @todo: add no_cursor_timeout option
    def flags(flags = [])
      flags << :slave_ok if secondary?
    end

    def needs_read_pref
      @client.mongos? &&
      !primary? &&
      (!secondary_preferred? || tags_set?)
    end

    # @todo: Emily: do this.
    def check_err_doc(doc)
      doc
    end

    def query_limit
      @scope.limit || 0
    end

    def remaining_limit
      query_limit - @returned
    end

    def batch_size
      return query_limit unless @scope.batch_size
      @scope.batch_size > 0 ? @scope.batch_size : query_limit
    end

    def to_return
      if limited?
        batch_size < remaining_limit ? batch_size : remaining_limit
      else
        batch_size
      end
    end

    def limited?
      query_limit > 0
    end

    def closed?
      @cursor_id == 0
    end

    def read
      @scope.read
    end

    def db_name
      @collection.database.name
    end

    def coll_name
      @collection.name
    end

    def query_run?
      !@node.nil?
    end

    def finished_requests?
      return closed? unless limited?
      @returned >= query_limit
    end

    # @todo: verify client interface
    def secondary_preferred?
      @client.secondary_preferred?(read)
    end

    def secondary?
      @client.secondary?(read)
    end

    def primary?
      @client.primary?(read)
    end

    def tags_set?
      @client.tags_set?(read)
    end

    def selector
      @scope.selector
    end

    def max_scan
      @scope.query_opts[:max_scan]
    end

    def snapshot
      @scope.query_opts[:snapshot]
    end

    def show_disk_loc
      @scope.query_opts[:show_disk_loc]
    end

    def sort
      @scope.sort
    end

    def hint
      @scope.hint
    end

    def comment
      @scope.comment
    end

  end
end