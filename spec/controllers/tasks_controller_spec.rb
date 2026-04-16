# frozen_string_literal: true

require "rails_helper"

RSpec.describe TasksController, type: :controller do
  let(:user) { create(:user, :owner) }

  before { sign_in user }

  # ─── GET #index ───────────────────────────────────────────────

  describe "GET #index" do
    let!(:backlog) { create(:task, status: "backlog", title: "Backlog item") }
    let!(:in_prog) { create(:task, :in_progress, title: "In flight") }

    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns tasks grouped by status" do
      get :index
      expect(assigns(:tasks_by_status)["backlog"]).to include(backlog)
      expect(assigns(:tasks_by_status)["in_progress"]).to include(in_prog)
    end

    it "includes open and done counts" do
      create(:task, :done)
      get :index
      expect(assigns(:total_open)).to be >= 2
      expect(assigns(:total_done)).to eq(1)
    end

    it "assigns all visible enabled agents" do
      create(:agent, system_agent: false, enabled: true)
      get :index
      expect(assigns(:agents)).to be_present
    end

    it "covers every STATUSES column in the grouped hash" do
      get :index
      expect(assigns(:tasks_by_status).keys).to match_array(Task::STATUSES)
    end

    context "when not authenticated" do
      before { sign_out user }

      it "redirects to sign in" do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  # ─── GET #show ────────────────────────────────────────────────

  describe "GET #show" do
    let!(:task) { create(:task) }

    it "returns a successful response" do
      get :show, params: { id: task.id }
      expect(response).to be_successful
    end

    it "assigns @task" do
      get :show, params: { id: task.id }
      expect(assigns(:task)).to eq(task)
    end

    it "raises not found for missing task" do
      expect {
        get :show, params: { id: 999999 }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  # ─── GET #new ─────────────────────────────────────────────────

  describe "GET #new" do
    it "returns a successful response" do
      get :new
      expect(response).to be_successful
    end

    it "builds a new task with default values" do
      get :new
      expect(assigns(:task)).to be_a_new(Task)
      expect(assigns(:task).status).to eq("backlog")
      expect(assigns(:task).priority).to eq("medium")
    end
  end

  # ─── POST #create ─────────────────────────────────────────────

  describe "POST #create" do
    let(:valid_params) do
      { task: { title: "New task", status: "backlog", priority: "medium" } }
    end

    context "with valid params" do
      it "creates a task" do
        expect { post :create, params: valid_params }.to change(Task, :count).by(1)
      end

      it "redirects to tasks index" do
        post :create, params: valid_params
        expect(response).to redirect_to(tasks_path)
      end

      it "sets a success notice" do
        post :create, params: valid_params
        expect(flash[:notice]).to eq("Task created.")
      end
    end

    context "with invalid params" do
      let(:invalid_params) { { task: { title: "", status: "backlog", priority: "medium" } } }

      it "does not create a task" do
        expect { post :create, params: invalid_params }.not_to change(Task, :count)
      end

      it "re-renders new" do
        post :create, params: invalid_params
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  # ─── PATCH #update ────────────────────────────────────────────

  describe "PATCH #update" do
    let!(:task) { create(:task, title: "Original title") }

    context "with valid params (HTML)" do
      it "updates the task" do
        patch :update, params: { id: task.id, task: { title: "Updated title" } }
        expect(task.reload.title).to eq("Updated title")
      end

      it "redirects to tasks index" do
        patch :update, params: { id: task.id, task: { title: "Updated title" } }
        expect(response).to redirect_to(tasks_path)
      end
    end

    context "with valid params (JSON)" do
      it "returns JSON success" do
        patch :update, params: { id: task.id, task: { title: "JSON title" } }, format: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
        expect(body["task"]["title"]).to eq("JSON title")
      end
    end

    context "with invalid params (JSON)" do
      it "returns 422 with error messages" do
        patch :update, params: { id: task.id, task: { title: "" } }, format: :json
        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body["errors"]).to be_present
      end
    end

    context "with a comment body" do
      it "adds a comment and redirects to show" do
        patch :update, params: { id: task.id, task: { status: task.status, _comment_body: "Nice work" } }
        task.reload
        expect(task.comments.size).to eq(1)
        expect(task.comments.first["body"]).to eq("Nice work")
        expect(response).to redirect_to(task_path(task))
      end

      it "does not trigger a regular update when _comment_body is present" do
        original_title = task.title
        patch :update, params: { id: task.id, task: { title: "Sneaky change", _comment_body: "A comment" } }
        expect(task.reload.title).to eq(original_title)
      end
    end

    context "when task does not exist" do
      it "raises not found" do
        expect {
          patch :update, params: { id: 999999, task: { title: "x" } }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ─── PATCH #move ──────────────────────────────────────────────

  describe "PATCH #move" do
    let!(:task) { create(:task, status: "backlog") }

    it "moves the task to the requested status" do
      patch :move, params: { id: task.id, status: "in_progress" }, format: :json
      expect(task.reload.status).to eq("in_progress")
      expect(response).to have_http_status(:ok)
    end

    it "returns JSON with updated task" do
      patch :move, params: { id: task.id, status: "done" }, format: :json
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ok")
      expect(body["task"]["status"]).to eq("done")
    end

    it "returns the full task JSON payload" do
      patch :move, params: { id: task.id, status: "todo" }, format: :json
      body = JSON.parse(response.body)
      expect(body["task"].keys).to include("id", "title", "status", "priority")
    end

    it "returns 422 for invalid status" do
      patch :move, params: { id: task.id, status: "nonexistent" }, format: :json
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Invalid status")
    end

    it "does not change status when given an invalid value" do
      patch :move, params: { id: task.id, status: "nonexistent" }, format: :json
      expect(task.reload.status).to eq("backlog")
    end

    context "when task does not exist" do
      it "raises not found" do
        expect {
          patch :move, params: { id: 999999, status: "todo" }, format: :json
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when not authenticated" do
      before { sign_out user }

      it "returns a redirect or 401" do
        patch :move, params: { id: task.id, status: "todo" }, format: :json
        expect(response.status).to be_in([302, 401])
      end
    end
  end

  # ─── DELETE #destroy ──────────────────────────────────────────

  describe "DELETE #destroy" do
    let!(:task) { create(:task) }

    it "destroys the task" do
      expect { delete :destroy, params: { id: task.id } }.to change(Task, :count).by(-1)
    end

    it "redirects to tasks index" do
      delete :destroy, params: { id: task.id }
      expect(response).to redirect_to(tasks_path)
    end

    it "sets a notice" do
      delete :destroy, params: { id: task.id }
      expect(flash[:notice]).to eq("Task deleted.")
    end

    context "when task does not exist" do
      it "raises not found" do
        expect {
          delete :destroy, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ─── PATCH #archive ───────────────────────────────────────────

  describe "PATCH #archive" do
    let!(:done_task) { create(:task, :done) }
    let!(:open_task) { create(:task, status: "in_progress") }

    it "archives a done task" do
      patch :archive, params: { id: done_task.id }
      expect(done_task.reload.archived_at).to be_present
    end

    it "redirects to tasks index with a notice" do
      patch :archive, params: { id: done_task.id }
      expect(response).to redirect_to(tasks_path)
      expect(flash[:notice]).to eq("Task archived.")
    end

    it "rejects archiving a non-done task and redirects with alert" do
      patch :archive, params: { id: open_task.id }
      expect(open_task.reload.archived_at).to be_nil
      expect(response).to redirect_to(tasks_path)
      expect(flash[:alert]).to match(/only completed tasks/i)
    end

    it "raises not found for missing task" do
      expect {
        patch :archive, params: { id: 999999 }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

end
