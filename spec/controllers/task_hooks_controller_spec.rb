# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskHooksController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:team) { create(:team) }
  let(:skill) { create(:skill) }

  before { sign_in user }

  describe "GET #index" do
    it "returns a successful response" do
      get :index, params: { team_id: team.id }
      expect(response).to be_successful
    end

    it "assigns @team and @hooks" do
      hook = create(:task_hook, :for_team, team: team, skill: skill)
      get :index, params: { team_id: team.id }
      expect(assigns(:team)).to eq(team)
      expect(assigns(:hooks)).to include(hook)
    end

    it "assigns @skills for the form" do
      create(:skill, :enabled)
      get :index, params: { team_id: team.id }
      expect(assigns(:skills)).to be_present
    end

    context "when not authenticated" do
      before { sign_out user }

      it "redirects to sign in" do
        get :index, params: { team_id: team.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        team_id: team.id,
        task_hook: { trigger: "post", on_status: "in_progress", skill_id: skill.id }
      }
    end

    it "creates a new team-level hook" do
      expect {
        post :create, params: valid_params
      }.to change(TaskHook, :count).by(1)
    end

    it "redirects to the hooks index" do
      post :create, params: valid_params
      expect(response).to redirect_to(team_task_hooks_path(team))
    end

    it "sets the team association" do
      post :create, params: valid_params
      expect(TaskHook.last.team).to eq(team)
    end

    it "creates a hook without a skill" do
      params = {
        team_id: team.id,
        task_hook: { trigger: "post", on_status: "in_progress", skill_id: "" }
      }
      expect {
        post :create, params: params
      }.to change(TaskHook, :count).by(1)
      expect(TaskHook.last.skill).to be_nil
    end

    context "with invalid params" do
      it "re-renders index on failure" do
        post :create, params: { team_id: team.id, task_hook: { trigger: "invalid", on_status: "in_progress" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET #edit" do
    let!(:hook) { create(:task_hook, :for_team, team: team, skill: skill) }

    it "returns a successful response" do
      get :edit, params: { team_id: team.id, id: hook.id }
      expect(response).to be_successful
    end

    it "assigns @hook" do
      get :edit, params: { team_id: team.id, id: hook.id }
      expect(assigns(:hook)).to eq(hook)
    end
  end

  describe "PATCH #update" do
    let!(:hook) { create(:task_hook, :for_team, team: team, skill: skill, on_status: "done") }

    it "updates the hook and redirects" do
      patch :update, params: { team_id: team.id, id: hook.id, task_hook: { on_status: "review" } }
      expect(response).to redirect_to(team_task_hooks_path(team))
      expect(hook.reload.on_status).to eq("review")
    end

    context "with invalid params" do
      it "re-renders edit" do
        patch :update, params: { team_id: team.id, id: hook.id, task_hook: { trigger: "invalid" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE #destroy" do
    let!(:hook) { create(:task_hook, :for_team, team: team, skill: skill) }

    it "removes the hook" do
      expect {
        delete :destroy, params: { team_id: team.id, id: hook.id }
      }.to change(TaskHook, :count).by(-1)
    end

    it "redirects to hooks index" do
      delete :destroy, params: { team_id: team.id, id: hook.id }
      expect(response).to redirect_to(team_task_hooks_path(team))
    end
  end

  describe "PATCH #toggle" do
    let!(:hook) { create(:task_hook, :for_team, team: team, skill: skill, enabled: true) }

    it "toggles enabled to false" do
      patch :toggle, params: { team_id: team.id, id: hook.id }
      expect(hook.reload.enabled?).to be false
    end

    it "toggles enabled back to true" do
      hook.update!(enabled: false)
      patch :toggle, params: { team_id: team.id, id: hook.id }
      expect(hook.reload.enabled?).to be true
    end

    it "redirects to hooks index" do
      patch :toggle, params: { team_id: team.id, id: hook.id }
      expect(response).to redirect_to(team_task_hooks_path(team))
    end
  end
end
