# frozen_string_literal: true

require "json"

# Minimal stdio MCP server for specs. Replies to initialize, tools/list and
# tools/call; call results carry this process's pid. Calling "die" exits it.
$stdout.sync = true
$stdin.each_line do |line|
  msg = JSON.parse(line)
  next unless msg["id"]

  result = case msg["method"]
  when "initialize" then { "protocolVersion" => "2025-03-26", "capabilities" => {} }
  when "tools/list" then { "tools" => [ { "name" => "echo", "description" => "Echo" } ] }
  when "tools/call"
    exit! if msg.dig("params", "name") == "die"
    if msg.dig("params", "name") == "fail"
      puts({ "jsonrpc" => "2.0", "id" => msg["id"], "error" => { "code" => -32_000, "message" => "tool exploded" } }.to_json)
      next
    end
    { "content" => [ { "type" => "text", "text" => "pid=#{Process.pid}" } ] }
  end
  puts({ "jsonrpc" => "2.0", "id" => msg["id"], "result" => result }.to_json)
end
