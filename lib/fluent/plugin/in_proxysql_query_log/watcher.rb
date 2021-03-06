module Fluent
  module Plugin
    class ProxysqlQueryLogInput < Fluent::Plugin::Input
      class Watcher < Coolio::StatWatcher
        def initialize(path, interval, pos_storage, router, tag, log)
          super(path, interval)

          @parser = ProxysqlQueryLog::Parser.new
          @pos_storage = pos_storage
          @router = router
          @tag = tag
          @log = log
          @attached = false
          read
        end

        def seek(path)
          cursor = @pos_storage.get(path)
          @io.seek(cursor, IO::SEEK_SET) if cursor
        end

        def on_change(previous, current)
          if current.nlink == 0
            @log.debug("stop watch: #{@path} (deleted)")
            @pos_storage.delete(@path)
            detach
          else
            read
          end
        end

        def read
          @io = File.open(@path)
          seek(@path)

          while true
            @pos = @io.pos
            raw_total_bytes = @io.read(8)
            return unless raw_total_bytes

            query = @parser.parse(@io)
            @router.emit(@tag, query.start_time/1000/1000, record(query))
            @pos_storage.put(@path, @io.pos)
          end

        ensure
          @io.close
        end

        def record(query)
          {
              'thread_id' => query.thread_id,
              'username' => query.username,
              'schema_name' => query.schema_name,
              'client' => query.client,
              'HID' => query.hid,
              'server' => query.server,
              'start_time' => convert_time(query.start_time),
              'end_time' => convert_time(query.end_time),
              'duration' => query.end_time - query.start_time,
              'digest' => query.digest,
              'query' => query.query,
              'hostname' => hostname,
              'filename' => @path,
              'pos' => @pos
          }
        end

        def convert_time(t)
          Time.at(t/1000/1000).utc.strftime('%Y-%m-%d %H:%M:%S')
        end

        def attach(loop)
          @attached = true
          super
        end

        def detach
          @attached = false
          super
        end
        def attached?
          @attached
        end

        def hostname
          @hostname ||= Socket.gethostname
        end
      end
    end
  end
end