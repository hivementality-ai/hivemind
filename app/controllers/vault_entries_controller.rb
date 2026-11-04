# frozen_string_literal: true

# Vault screen: shared (global) secrets, by namespace and key.
#
# Values are write-only here. The page shows that a key is set and when it was last
# updated, never the value, so nothing a person can see in the browser holds a secret.
class VaultEntriesController < ApplicationController
  before_action :authorize_admin_or_owner!
  before_action :set_entry, only: %i[edit update destroy]

  def index
    @entries = VaultEntry.global.order(:namespace, :key)
  end

  def new
    @entry = VaultEntry.new(namespace: params[:namespace])
  end

  def create
    namespace = entry_params[:namespace].to_s.strip
    key = entry_params[:key].to_s.strip
    if VaultEntry.global.exists?(namespace:, key:)
      return reject(:new, VaultEntry.new(namespace:, key:), "#{namespace}/#{key} already exists. Use Replace value on it instead.")
    end

    save_value(namespace:, key:, template: :new)
  end

  def edit; end

  def update
    save_value(namespace: @entry.namespace, key: @entry.key, template: :edit)
  end

  def destroy
    @entry.destroy!
    Audit::Record.call(
      actor_type: "user", actor_id: current_user.id, action: "vault.delete",
      resource: "vault_entries/#{@entry.id}", metadata: { namespace: @entry.namespace, key: @entry.key }
    )
    redirect_to vault_entries_path, notice: "Key #{@entry.namespace}/#{@entry.key} deleted."
  end

  private

  def set_entry
    @entry = VaultEntry.global.find(params[:id])
  end

  def entry_params
    params.require(:vault_entry).permit(:namespace, :key, :value)
  end

  def save_value(namespace:, key:, template:)
    value = entry_params[:value].to_s
    return reject(template, @entry || VaultEntry.new(namespace:, key:), "Value can't be blank.") if value.blank?

    result = Vault::Write.call(namespace:, key:, value:)
    return redirect_to(vault_entries_path, notice: "Key #{namespace}/#{key} saved.") if result.success?

    reject(template, @entry || VaultEntry.new(namespace:, key:), Array(result.error).join(", "))
  end

  def reject(template, entry, message)
    @entry = entry
    flash.now[:alert] = message
    render template, status: :unprocessable_entity
  end
end
