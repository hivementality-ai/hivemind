# frozen_string_literal: true

class KnowledgeDocumentsController < ApplicationController
  before_action :authorize_admin_or_owner!, only: [ :new, :create, :destroy ]
  before_action :set_document, only: [ :show, :destroy ]

  def index
    @documents = KnowledgeDocument.includes(:chunks).order(created_at: :desc)
  end

  def show
    @chunks = @document.chunks.order(:position)
  end

  def new
    @document = KnowledgeDocument.new
    @agents = Agent.enabled.order(:name)
  end

  def create
    @document = KnowledgeDocument.new(document_params)

    if save_source(@document) && @document.save
      KnowledgeIngestionJob.perform_later(@document.id)
      redirect_to knowledge_documents_path, notice: "Document queued for ingestion."
    else
      @agents = Agent.enabled.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy
    redirect_to knowledge_documents_path, notice: "Document deleted."
  end

  private

  def set_document
    @document = KnowledgeDocument.find(params[:id])
  end

  def document_params
    params.require(:knowledge_document).permit(:title, :agent_id, :source_type)
  end

  # Writes uploaded file or pasted text to local storage, sets source_url.
  # ponytail: flat file storage under storage/knowledge_documents — no ActiveStorage
  # needed since the job already reads from source_url paths.
  def save_source(document)
    dir = Rails.root.join("storage", "knowledge_documents")
    FileUtils.mkdir_p(dir)

    case document.source_type
    when "pdf"
      upload = params.dig(:knowledge_document, :file)
      unless upload.respond_to?(:read)
        document.errors.add(:base, "Please upload a PDF file.")
        return false
      end
      path = dir.join("#{SecureRandom.hex(8)}.pdf")
      File.binwrite(path, upload.read)
      document.source_url = path.to_s
    else
      text = params.dig(:knowledge_document, :text_content).to_s.strip
      if text.blank?
        document.errors.add(:base, "Please enter text content.")
        return false
      end
      path = dir.join("#{SecureRandom.hex(8)}.txt")
      File.write(path, text)
      document.source_url = path.to_s
    end

    true
  end
end
