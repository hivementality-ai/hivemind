# frozen_string_literal: true

require "shellwords"

module Mcp
  # Finds secrets passed as stdio command arguments and swaps each for a
  # "vault:<namespace>/<key>" reference, so the command column never holds them.
  #
  # An argument counts as a secret when it is the value of a flag named like a
  # token, key, secret, password or auth (either "--api-key VALUE" or
  # "--api-key=VALUE"), or when it starts with a well-known key prefix.
  class CommandSecrets
    Result = Struct.new(:command, :writes, keyword_init: true)

    FLAG = /\A--?(?:[a-z0-9]+[-_])*(?:token|api[-_]?key|apikey|key|secret|password|auth)\z/i
    KEY_PREFIX = /\A(?:sk-|ghp_|github_pat_|xox[bpa]-|lin_api_|secret_|ntn_)/
    VAULT_REF = %r{\Avault:([^/\s=]+)/(\S+)\z}

    # @param command [String] the stdio command line
    # @param namespace [String] vault namespace for the extracted values
    # @return [Result] +command+ with references in place of secrets, and +writes+ as [namespace, key, value] triples
    def self.extract(command, namespace:)
      new(command, namespace).extract
    end

    # @param command [String] a command line that may hold "vault:" references
    # @return [Array<String>] its arguments with each reference replaced by the vaulted value
    def self.resolve(command)
      Shellwords.shellsplit(command.to_s).map { |arg| resolve_arg(arg) }
    end

    # Replaces a whole-argument or "--flag=" reference; an unknown reference is left as written.
    def self.resolve_arg(arg)
      prefix, ref = arg.include?("=") && !arg.start_with?("vault:") ? arg.split("=", 2) : [ nil, arg ]
      match = VAULT_REF.match(ref)
      return arg unless match

      value = VaultEntry.find_by(namespace: match[1], key: match[2])&.value
      return arg unless value

      prefix ? "#{prefix}=#{value}" : value
    end
    private_class_method :resolve_arg

    def initialize(command, namespace)
      @command = command.to_s
      @namespace = namespace
      @writes = []
    end

    def extract
      args = Shellwords.shellsplit(@command)
      replaced = args.dup
      flag = nil
      args.each_with_index do |arg, index|
        next if index.zero?

        flag, replaced[index] = scan(arg, flag, index)
      end
      return Result.new(command: @command, writes: []) if @writes.empty?

      Result.new(command: join(replaced), writes: @writes)
    rescue ArgumentError
      Result.new(command: @command, writes: [])
    end

    private

    # Shell-joins the arguments, leaving "--flag=vault:ns/key" readable.
    def join(args)
      args.map { |arg| arg.match?(%r{\A[\w.-]+=vault:[\w./-]+\z}) ? arg : arg.shellescape }.join(" ")
    end

    # @return [Array] the flag awaiting a value (or nil) and the argument to keep
    def scan(arg, flag, index)
      return [ nil, vault(flag, arg) ] if flag && secret_value?(arg)

      name, value = arg.split("=", 2)
      return [ nil, "#{name}=#{vault(name, value)}" ] if value && name.match?(FLAG) && secret_value?(value)
      return [ nil, vault("arg_#{index}", arg) ] if arg.match?(KEY_PREFIX)

      [ (arg.match?(FLAG) ? arg : nil), arg ]
    end

    def secret_value?(value)
      value.present? && !value.start_with?("-", "/", "./", "../", "~") && !value.match?(VAULT_REF)
    end

    def vault(label, value)
      key = "arg_#{label.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '').delete_prefix('arg_')}"
      key = "#{key}_#{@writes.size + 1}" if @writes.any? { |_, k, _| k == key }
      @writes << [ @namespace, key, value ]
      "vault:#{@namespace}/#{key}"
    end
  end
end
