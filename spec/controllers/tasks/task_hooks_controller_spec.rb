# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::TaskHooksController, type: :controller do
  let(:user)  { create(:user, :owner) }
  let(:task)  { create(:task) }
  let(:skill) { create(:skill) }

  before { sign_in user }

  # ─── POST #create ──────────────────────────────────────────────

  describe "POST #create" do
    let(:valid_params) do
      {
        task_id:   task.id,
        task_hook: { trigger: "post", on_status: "done", skill_id: skill.id }
      }
    end

    it "creates a hook on the task" do
      expect {
        post :create, params: valid_params
      }.to change(TaskHook, :count).by(1)
    end

    it "associates the hook with the correct task" do
      post :create, params: valid_params
      expect(TaskHook.last.task).to eq(task)
    end

    it "sets position to current hook count before save" do
      create(:task_hook, :for_task, task: task, skill: skill)
      post :create, params: valid_params
      expect(TaskHook.last.position).to eq(1)
    end

    it "redirects to the task edit page with a notice" do
      post :create, params: valid_params
      expect(response).to redirect_to(edit_task_path(task))
      expect(flash[:notice]).to eq("Hook added.")
    end

    context "when skill_id is missing" do
      it "does not create a hook" do
        expect {
          post :create, params: {
            task_id:   task.id,
            task_hook: { trigger: "post", on_status: "done", skill_id: "" }
          }
        }.not_to change(TaskHook, :count)
      end

      it "redirects with an alert" do
        post :create, params: {
          task_id:   task.id,
          task_hook: { trigger: "post", on_status: "done", skill_id: "" }
        }
        expect(response).to redirect_to(edit_task_path(task))
        expect(flash[:alert]).to be_present
      end
    end

    context "when trigger is invalid" do
      it "does not create a hook" do
        expect {
          post :create, params: {
            task_id:   task.id,
            task_hook: { trigger: "invalid", on_status: "done", skill_id: skill.id }
          }
        }.not_to change(TaskHook, :count)
      end

      it "redirects with an alert" do
        post :create, params: {
          task_id:   task.id,
          task_hook: { trigger: "invalid", on_status: "done", skill_id: skill.id }
        }
        expect(response).to redirect_to(edit_task_path(task))
        expect(flash[:alert]).to be_present
      end
    end

    context "when task does not exist" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          post :create, params: {
            task_id:   0,
            task_hook: { trigger: "post", on_status: "done", skill_id: skill.id }
          }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when not authenticated" do
      before { sign_out user }

      it "redirects to sign in" do
        post :create, params: valid_params
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  # ─── DELETE #destroy ───────────────────────────────────────────

  describe "DELETE #destroy" do
    let!(:hook) { create(:task_hook, :for_task, task: task, skill: skill) }

    it "removes the hook" do
      expect {
        delete :destroy, params: { task_id: task.id, id: hook.id }
      }.to change(TaskHook, :count).by(-1)
    end

    it "redirects to the task edit page with a notice" do
      delete :destroy, params: { task_id: task.id, id: hook.id }
      expect(response).to redirect_to(edit_task_path(task))
      expect(flash[:notice]).to eq("Hook removed.")
    end

    context "when hook belongs to a different task" do
      let(:other_task) { create(:task) }
      let!(:other_hook) { create(:task_hook, :for_task, task: other_task, skill: skill) }

      it "redirects with an alert" do
        delete :destroy, params: { task_id: task.id, id: other_hook.id }
        expect(response).to redirect_to(edit_task_path(task))
        expect(flash[:alert]).to eq("Hook not found.")
      end
    end

    context "when hook does not exist" do
      it "redirects with an alert" do
        delete :destroy, params: { task_id: task.id, id: 0 }
        expect(response).to redirect_to(edit_task_path(task))
        expect(flash[:alert]).to eq("Hook not found.")
      end
    end

    context "when not authenticated" do
      before { sign_out user }

      it "redirects to sign in" do
        delete :destroy, params: { task_id: task.id, id: hook.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
