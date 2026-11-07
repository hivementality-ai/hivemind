# frozen_string_literal: true

require "find"

module Library
  # Walks the watched library folder and keeps the knowledge base in step with
  # it: new and changed files are (re)ingested, files that disappear are marked
  # removed (their chunks stay, so earlier citations still resolve).
  class FolderScan
    SOURCE_TYPES = { ".pdf" => "pdf", ".txt" => "text", ".md" => "text" }.freeze
    MAX_BYTES = 50.megabytes
    SETTLE_SECONDS = 10

    Result = Struct.new(:added, :updated, :unchanged, :removed, :skipped, :errors, keyword_init: true) do
      def self.empty = new(added: 0, updated: 0, unchanged: 0, removed: 0, skipped: 0, errors: 0)
    end

    # @param root [Pathname, String] the folder to watch
    def initialize(root: FolderSetting.root)
      @root = Pathname.new(root)
      @result = Result.empty
    end

    # @return [Result] counts for this scan
    def call
      return @result unless @root.directory? && (@agent = FolderSetting.agent)

      @real_root = @root.realpath
      seen = candidate_files.each_with_object([]) { |path, paths| paths << relative(path) if sync(path) }
      mark_removed(seen)
      FolderSetting.record_scan(@result)
      @result
    end

    private

    def candidate_files
      Enumerator.new do |yielder|
        Find.find(@real_root.to_s) do |path|
          name = File.basename(path)
          if File.symlink?(path) || (path != @real_root.to_s && ignored_name?(name))
            @result.skipped += 1 unless File.directory?(path) && !File.symlink?(path)
            Find.prune
          elsif File.file?(path)
            yielder << Pathname.new(path)
          end
        end
      end
    end

    def ignored_name?(name)
      name.start_with?(".", "~$") || name.end_with?("~")
    end

    # @return [Boolean] true when the file is part of the library
    def sync(path)
      return false unless supported?(path)
      return true unless readable_now?(path)

      rel = relative(path)
      signature = signature_for(path)
      doc = KnowledgeDocument.find_by(agent: @agent, library_path: rel)

      if doc.nil?
        ingest(path, rel, signature, KnowledgeDocument.new(agent: @agent, library_path: rel))
        @result.added += 1
      elsif doc.library_signature != signature || doc.removed_at
        ingest(path, rel, signature, doc)
        @result.updated += 1
      else
        @result.unchanged += 1
      end
      true
    rescue StandardError => e
      @result.errors += 1
      Rails.logger.error("[Library::FolderScan] #{path}: #{e.message}")
      true
    end

    def supported?(path)
      ok = SOURCE_TYPES.key?(path.extname.downcase) && inside_root?(path)
      @result.skipped += 1 unless ok
      ok
    end

    # False for empty or oversized files and ones still being written; they
    # stay in the library but are not (re)ingested yet.
    def readable_now?(path)
      stat = path.stat
      ok = stat.size.positive? && stat.size <= MAX_BYTES && stat.mtime <= SETTLE_SECONDS.seconds.ago
      @result.skipped += 1 unless ok
      ok
    end

    def inside_root?(path)
      path.realpath.to_s.start_with?("#{@real_root}/")
    end

    def signature_for(path)
      stat = path.stat
      "#{stat.size}:#{stat.mtime.to_i}"
    end

    def relative(path)
      path.relative_path_from(@real_root).to_s
    end

    # Copies the file into app storage (the ingestion job reads from there and
    # the watched folder stays read-only), then queues extraction.
    def ingest(path, rel, signature, doc)
      old_copy = doc.source_url if doc.persisted?
      doc.assign_attributes(
        title: path.basename(path.extname).to_s, source_type: SOURCE_TYPES.fetch(path.extname.downcase),
        source_url: copy_into_storage(path), library_signature: signature,
        status: "pending", error: nil, removed_at: nil
      )
      doc.save!
      File.delete(old_copy) if old_copy.present? && old_copy != doc.source_url && File.exist?(old_copy)
      KnowledgeIngestionJob.perform_later(doc.id)
    end

    def copy_into_storage(path)
      dir = Rails.root.join("storage", "knowledge_documents")
      FileUtils.mkdir_p(dir)
      dest = dir.join("library-#{SecureRandom.hex(8)}#{path.extname.downcase}")
      FileUtils.cp(path, dest)
      dest.to_s
    end

    def mark_removed(seen)
      gone = KnowledgeDocument.where(agent: @agent, removed_at: nil).where.not(library_path: nil)
                              .where.not(library_path: seen)
      @result.removed += gone.update_all(removed_at: Time.current)
    end
  end
end
