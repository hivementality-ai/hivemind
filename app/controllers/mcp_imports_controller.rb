# frozen_string_literal: true

# Imports MCP servers from a Claude Desktop config: paste it (or read it from
# this Mac), tick the servers to bring over, and import.
#
# Env and header values never come back to the page. The preview lists only
# their names and carries the parsed entries forward in an encrypted token.
class McpImportsController < ApplicationController
  TOKEN_TTL = 30.minutes

  before_action :authorize_admin_or_owner!

  def new
    @local_available = request.local? && Mcp::DesktopImport.read_local.present?
  end

  def preview
    text = params[:from_mac].present? && request.local? ? Mcp::DesktopImport.read_local : params[:config_json]
    @entries = Mcp::DesktopImport.parse(text)
    @token = encryptor.encrypt_and_sign(@entries.map(&:to_payload), expires_in: TOKEN_TTL)
  rescue Mcp::DesktopImport::Error => e
    @local_available = request.local? && Mcp::DesktopImport.read_local.present?
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def create
    payloads = encryptor.decrypt_and_verify(params[:token].to_s) || []
    chosen = Array(params[:names]).map(&:to_s)
    result = Mcp::DesktopImport.import!(payloads.select { |payload| chosen.include?(payload["name"]) })
    redirect_to mcp_servers_path, notice: import_notice(result)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    redirect_to new_mcp_import_path, alert: "That preview expired. Paste the config again."
  end

  private

  def encryptor
    key = Rails.application.key_generator.generate_key("mcp desktop import", ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key, serializer: JSON)
  end

  def import_notice(result)
    notice = "Imported #{result[:imported].size} #{'server'.pluralize(result[:imported].size)}."
    notice += " Skipped #{result[:skipped].to_sentence} (already added or invalid)." if result[:skipped].any?
    notice
  end
end
