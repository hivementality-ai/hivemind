# frozen_string_literal: true

module Api
  module V1
    class PlansController < ApplicationController
      before_action :authenticate_user!

      # POST /api/v1/plans/save
      def save
        filename = params[:filename]&.strip
        content = params[:content]&.strip
        location = params[:location] || "workspace"

        unless filename.present? && content.present?
          return render json: { success: false, error: "Filename and content are required" }, status: :unprocessable_entity
        end

        case location
        when "workspace"
          result = save_to_workspace(filename, content)
        else
          result = { success: false, error: "Invalid location" }
        end

        render json: result
      rescue StandardError => e
        Rails.logger.error("Plans save error: #{e.message}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      def save_to_workspace(filename, content)
        # Sanitize filename
        safe_filename = File.basename(filename).gsub(/[^a-zA-Z0-9._-]/, "_")
        
        # Ensure plans directory exists
        plans_dir = "/workspace/plans"
        FileUtils.mkdir_p(plans_dir) unless Dir.exist?(plans_dir)
        
        # Write file
        filepath = File.join(plans_dir, safe_filename)
        File.write(filepath, content)
        
        {
          success: true,
          message: "Plan summary saved",
          filename: safe_filename,
          path: filepath
        }
      end
    end
  end
end
