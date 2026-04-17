# frozen_string_literal: true

module SwarmImportsHelper
  # Returns a path to view a deployed entity record, or nil if no route exists.
  # Used by the post-deploy report to render "View →" links.
  def record_link_path(record)
    return nil if record.nil?

    case record
    when Agent  then agent_path(record)
    when Skill  then skill_path(record)
    when Tool   then tool_path(record)
    when Team   then edit_team_path(record)
    else             nil
    end
  rescue ActionController::UrlGenerationError
    nil
  end
end
