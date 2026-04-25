# frozen_string_literal: true

require "rails_helper"

RSpec.describe SwarmImportsController, type: :controller do
  let(:user) { create(:user, :owner) }

  # Use an in-memory cache so specs don't bleed state.
  around(:each) do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  before { sign_in user }

  # -------------------------------------------------------------------------
  # Minimal valid .swarm.json fixture shared across specs.
  # -------------------------------------------------------------------------
  let(:valid_swarm_json) do
    JSON.generate({
      swarm_version: "1.0",
      name:          "Spec Swarm",
      slug:          "spec-swarm",
      team:          { name: "Spec Team" },
      agents:        [],
      skills:        [],
      tools:         []
    })
  end

  let(:valid_swarm_file) do
    file = Tempfile.new(["spec_swarm", ".swarm.json"])
    file.write(valid_swarm_json)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "spec_swarm.swarm.json")
  end

  let(:swarm_with_variables_json) do
    JSON.generate({
      swarm_version: "1.0",
      name:          "Var Swarm",
      slug:          "var-swarm",
      team:          { name: "Var Team", description: "{{ORG_NAME}}" },
      agents:        [],
      skills:        [],
      tools:         [],
      variables:     {
        "ORG_NAME" => { required: true,  type: "string", description: "Organisation name" },
        "API_URL"  => { required: false, type: "string", default: "https://example.com" }
      }
    })
  end

  let(:swarm_with_variables_file) do
    file = Tempfile.new(["var_swarm", ".swarm.json"])
    file.write(swarm_with_variables_json)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "var_swarm.swarm.json")
  end

  # -------------------------------------------------------------------------
  # GET #import_swarm
  # -------------------------------------------------------------------------
  describe "GET #import_swarm" do
    it "returns 200" do
      get :import_swarm
      expect(response).to have_http_status(:ok)
    end

    it "renders the import_swarm template" do
      get :import_swarm
      expect(response).to render_template(:import_swarm)
    end

    context "when not authenticated" do
      before { sign_out user }

      it "redirects to sign in" do
        get :import_swarm
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  # -------------------------------------------------------------------------
  # POST #upload_swarm
  # -------------------------------------------------------------------------
  describe "POST #upload_swarm" do
    context "with no file" do
      it "re-renders import_swarm with an error" do
        post :upload_swarm
        expect(response).to render_template(:import_swarm)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with an invalid file extension" do
      let(:txt_file) do
        Rack::Test::UploadedFile.new(
          StringIO.new("not json"),
          "text/plain",
          original_filename: "bad_file.txt"
        )
      end

      it "re-renders import_swarm with an error" do
        post :upload_swarm, params: { swarm_file: txt_file }
        expect(response).to render_template(:import_swarm)
        expect(flash[:alert]).to match(/invalid file type/i)
      end
    end

    context "with malformed JSON" do
      let(:bad_json_file) do
        Rack::Test::UploadedFile.new(
          StringIO.new("{ not valid json"),
          "application/json",
          original_filename: "bad.swarm.json"
        )
      end

      it "re-renders import_swarm with parse errors" do
        post :upload_swarm, params: { swarm_file: bad_json_file }
        expect(response).to render_template(:import_swarm)
        expect(assigns(:parse_errors)).not_to be_empty
      end
    end

    context "with a valid swarm file" do
      it "redirects to preview_swarm" do
        post :upload_swarm, params: { swarm_file: valid_swarm_file }
        expect(response).to redirect_to(preview_swarm_teams_path)
      end

      it "writes the parse result to the cache" do
        post :upload_swarm, params: { swarm_file: valid_swarm_file }
        key = session[:swarm_import_key]
        expect(key).to be_present
        cached = Rails.cache.read(key)
        expect(cached).to include(swarm_name: "Spec Swarm")
      end

      it "stores the raw JSON for later re-parsing" do
        post :upload_swarm, params: { swarm_file: valid_swarm_file }
        key = session[:swarm_import_key]
        cached = Rails.cache.read(key)
        expect(cached[:raw_json]).to be_present
      end

      it "stores serialized conflicts (empty for a fresh team name)" do
        post :upload_swarm, params: { swarm_file: valid_swarm_file }
        key = session[:swarm_import_key]
        cached = Rails.cache.read(key)
        expect(cached[:conflicts]).to eq([])
      end
    end

    context "with a swarm that has conflicting entity names" do
      let!(:existing_team) { create(:team, name: "Spec Team") }

      it "stores the conflict in the cache" do
        post :upload_swarm, params: { swarm_file: valid_swarm_file }
        key = session[:swarm_import_key]
        cached = Rails.cache.read(key)
        conflicts = cached[:conflicts]
        expect(conflicts).to include(
          a_hash_including(entity_type: "team", name: "Spec Team")
        )
      end

      it "still redirects to preview_swarm" do
        post :upload_swarm, params: { swarm_file: valid_swarm_file }
        expect(response).to redirect_to(preview_swarm_teams_path)
      end
    end
  end

  # -------------------------------------------------------------------------
  # GET #preview_swarm
  # -------------------------------------------------------------------------
  describe "GET #preview_swarm" do
    context "with no cached import" do
      it "redirects to import_swarm" do
        get :preview_swarm
        expect(response).to redirect_to(import_swarm_teams_path)
      end
    end

    context "with a cached import" do
      before do
        post :upload_swarm, params: { swarm_file: valid_swarm_file }
        # Clear multipart content-type left over from the file upload so
        # subsequent GET/POST requests don't trigger Rack::Multipart::EmptyContentError.
        request.env.delete("CONTENT_TYPE")
      end

      it "returns 200" do
        get :preview_swarm
        expect(response).to have_http_status(:ok)
      end

      it "renders the preview_swarm template" do
        get :preview_swarm
        expect(response).to render_template(:preview_swarm)
      end

      it "assigns @swarm_name from the cache" do
        get :preview_swarm
        expect(assigns(:swarm_name)).to eq("Spec Swarm")
      end

      it "assigns @conflicts as empty for a conflict-free swarm" do
        get :preview_swarm
        expect(assigns(:conflicts)).to eq([])
      end
    end

    context "with a swarm that has variables" do
      before do
        post :upload_swarm, params: { swarm_file: swarm_with_variables_file }
        request.env.delete("CONTENT_TYPE")
      end

      it "assigns @variables with all variable descriptors" do
        get :preview_swarm
        variable_names = assigns(:variables).map { |v| v[:name] }
        expect(variable_names).to contain_exactly("ORG_NAME", "API_URL")
      end
    end
  end

  # -------------------------------------------------------------------------
  # POST #confirm_swarm
  # -------------------------------------------------------------------------
  describe "POST #confirm_swarm" do
    context "with no cached import" do
      it "redirects to import_swarm" do
        post :confirm_swarm
        expect(response).to redirect_to(import_swarm_teams_path)
      end
    end

    context "with a valid swarm and no conflicts" do
      before do
        post :upload_swarm, params: { swarm_file: valid_swarm_file }
        request.env.delete("CONTENT_TYPE")
      end

      it "renders the report template on success" do
        post :confirm_swarm
        expect(response).to render_template(:report)
        expect(response).to have_http_status(:ok)
      end

      it "clears the cache key after a successful import" do
        key = session[:swarm_import_key]
        post :confirm_swarm
        expect(Rails.cache.read(key)).to be_nil
        expect(session[:swarm_import_key]).to be_nil
      end

      it "passes report locals to the template" do
        post :confirm_swarm
        # The :report local should be an ImportReport with a summary
        report = controller.view_assigns["report"] rescue nil
        # Template receives it as a local — check the response body instead
        expect(response.body).to include("Spec Swarm").or include("deployed")
      end
    end

    context "with variable overrides" do
      before do
        post :upload_swarm, params: { swarm_file: swarm_with_variables_file }
        request.env.delete("CONTENT_TYPE")
      end

      it "passes variable overrides to the importer" do
        expect(Swarms::SwarmImporter).to receive(:call).with(
          hash_including(variable_overrides: { "ORG_NAME" => "Acme Corp" })
        ).and_call_original

        post :confirm_swarm, params: { variables: { "ORG_NAME" => "Acme Corp" } }
      end
    end

    context "with conflict resolutions" do
      let!(:existing_team) { create(:team, name: "Spec Team") }
      before { post :upload_swarm, params: { swarm_file: valid_swarm_file } }

      it "passes resolutions to the importer" do
        expect(Swarms::SwarmImporter).to receive(:call).with(
          hash_including(resolutions: { "Spec Team" => :overwrite })
        ).and_call_original

        post :confirm_swarm, params: { resolutions: { "Spec Team" => "overwrite" } }
      end
    end

    context "when the importer fails (missing required variable)" do
      before { post :upload_swarm, params: { swarm_file: swarm_with_variables_file } }

      it "re-renders preview_swarm with the error" do
        # Don't supply the required ORG_NAME variable
        post :confirm_swarm, params: { variables: {} }
        expect(response).to render_template(:preview_swarm)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(assigns(:import_error)).to be_present
      end

      it "assigns @import_stage to :variables" do
        post :confirm_swarm, params: { variables: {} }
        expect(assigns(:import_stage)).to eq(:variables)
      end
    end
  end
end
