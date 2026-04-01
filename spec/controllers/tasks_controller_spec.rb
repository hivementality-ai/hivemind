# frozen_string_literal: true

require "rails_helper"

RSpec.describe TasksController, type: :controller do
  let(:user)  { create(:user, :owner) }
  let(:team)  { create(:team) }
  let(:agent) { create(:agent, :with_team, team: team) }

  before { sign_in user }

  describe "GET #index" do
    let!(:task_a) { create(:task, team: team, user: user, status: :todo) }
    let!(:task_b) { create(:task, team: team, user: user, status: :done) }

    before do
      # Give team at least one agent so filter builds correctly
      agent
    end

    it "returns 200" do
      get :index, params: { team_id: team.id }
      expect(response).to be_successful
    end

    it "assigns @tasks_by_status with tasks grouped by status" do
      get :index, params: { team_id: team.id }
      tasks_by_status = assigns(:tasks_by_status)
      expect(tasks_by_status["todo"]).to include(task_a)
      expect(tasks_by_status["done"]).to include(task_b)
    end

    it "filters by agent slug when provided" do
      assigned = create(:task, team: team, user: user, agent: agent)
      get :index, params: { team_id: team.id, agent_slug: agent.slug }
      tasks_by_status = assigns(:tasks_by_status)
      all_tasks = tasks_by_status.values.flatten
      expect(all_tasks).to include(assigned)
      expect(all_tasks).not_to include(task_a)
    end
  end

  describe "GET #show" do
    let!(:task) { create(:task, team: team, user: user) }

    it "returns 200" do
      get :show, params: { id: task.id }
      expect(response).to be_successful
    end

    it "assigns @task" do
      get :show, params: { id: task.id }
      expect(assigns(:task)).to eq(task)
    end
  end

  describe "GET #new" do
    it "returns 200" do
      get :new, params: { team_id: team.id }
      expect(response).to be_successful
    end

    it "assigns a new task" do
      get :new
      expect(assigns(:task)).to be_a_new(Task)
    end
  end

  describe "POST #create" do
    let(:valid_attrs) do
      { title: "New Task", status: "todo", priority: "medium", team_id: team.id }
    end

    it "creates a task and redirects to show" do
      expect {
        post :create, params: { task: valid_attrs }
      }.to change(Task, :count).by(1)
      expect(response).to redirect_to(task_path(Task.last))
    end

    it "sets created_by to 'user'" do
      post :create, params: { task: valid_attrs }
      expect(Task.last.created_by).to eq("user")
    end

    it "re-renders new on invalid params" do
      post :create, params: { task: valid_attrs.merge(title: "") }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "responds with JSON when requested" do
      post :create, params: { task: valid_attrs }, format: :json
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["title"]).to eq("New Task")
    end
  end

  describe "PATCH #update" do
    let!(:task) { create(:task, team: team, user: user, title: "Original") }

    it "updates the task and redirects to show" do
      patch :update, params: { id: task.id, task: { title: "Updated" } }
      expect(task.reload.title).to eq("Updated")
      expect(response).to redirect_to(task_path(task))
    end

    it "updates status (for drag-drop)" do
      patch :update, params: { id: task.id, task: { status: "in_progress" } }, format: :json
      expect(task.reload.status).to eq("in_progress")
      expect(response).to be_successful
    end

    it "re-renders edit on invalid params" do
      patch :update, params: { id: task.id, task: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE #destroy" do
    let!(:task) { create(:task, team: team, user: user) }

    it "destroys the task and redirects to index" do
      expect {
        delete :destroy, params: { id: task.id }
      }.to change(Task, :count).by(-1)
      expect(response).to redirect_to(tasks_path(team_id: team.id))
    end
  end
end
