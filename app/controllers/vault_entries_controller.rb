# frozen_string_literal: true

# User-facing management of the vault (shared, global secrets).
#
# Security model (enforced elsewhere, surfaced here):
#   - Users manage keys through this UI. Values are ALWAYS shown redacted —
#     never rendered in full, even to admins.
#   - Agents can never read a value: Tools::VaultExecutor only ever returns
#     Vault::Redactor output. Tools/skills the agent builds run server-side
#     and resolve the real value via VaultEntry#value, so a secret reaches the
#     tool code without ever passing through the agent.
class VaultEntriesController < ApplicationController
  before_action :authorize_admin_or_owner!

  def index
    # Global scope only — these are the shared secrets users manage.
    @entries = VaultEntry.global.order(:namespace, :key)
  end

  def new
    @entry = VaultEntry.new(namespace: params[:namespace])
  end

  def create
    result = Vault::Write.call(
      namespace: entry_params[:namespace].to_s.strip,
      key: entry_params[:key].to_s.strip,
      value: entry_params[:value].to_s,
      metadata: entry_params[:purpose].present? ? { "purpose" => entry_params[:purpose].strip } : {}
    )

    if result.success?
      redirect_to vault_entries_path, notice: "Key #{entry_params[:namespace]}.#{entry_params[:key]} saved."
    else
      @entry = VaultEntry.new(entry_params.except(:value))
      flash.now[:alert] = Array(result.error).join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    entry = VaultEntry.global.find(params[:id])
    entry.destroy!
    Audit::Record.call(
      actor_type: "user",
      actor_id: current_user.id,
      action: "vault.delete",
      resource: "vault_entries/#{entry.id}",
      metadata: { namespace: entry.namespace, key: entry.key }
    )
    redirect_to vault_entries_path, notice: "Key #{entry.namespace}.#{entry.key} deleted."
  end

  private

  def entry_params
    params.require(:vault_entry).permit(:namespace, :key, :value, :purpose)
  end
end
