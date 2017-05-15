# encoding: utf-8
require "azure/storage"

module Backup
  module Storage
    class AzureStore < Base
      include Storage::Cycler
      class Error < Backup::Error; end

      attr_accessor :storage_account, :storage_access_key, :container_name, :retry_count, :retry_interval

      def initialize(model, storage_id = nil)
        super
        @path           ||= "backups"
        @retry_count    ||= 3
        @retry_interval ||= 30
        path.sub!(%r{^/}, "")

        check_configuration

        Azure::Storage.setup(storage_account_name: storage_account, storage_access_key: storage_access_key)
      end

      def blob_service_with_retry_filter
        @blob_service_with_retry_filter = Azure::Storage::Blob::BlobService.new
        @blob_service_with_retry_filter.with_filter(Azure::Storage::Core::Filter::LinearRetryPolicyFilter.new(@retry_count, @retry_interval))
        @blob_service_with_retry_filter
      end

      def blob_service
        @blob_service ||= blob_service_with_retry_filter
      end

      def container
        @container ||= blob_service.get_container_properties(container_name)
      end

      def transfer!
        package.filenames.each do |filename|
          source_path = File.join(Config.tmp_path, filename)
          remote_path = File.join(source_path, filename)
          Logger.info "Storage::AzureStore uploading '#{container.name}/#{remote_path}'"
          blob_service.create_block_blob(container.name, remote_path, ::File.open(source_path, "rb", &:read))
        end
      end

      # Called by the Cycler.
      # Any error raised will be logged as a warning.
      def remove!(package)
        Logger.info "Removing backup package dated #{package.time}..."

        package.filenames.each do |filename|
          remote_path = "#{remote_path_for(package)}/#{filename}"
          Logger.info "Storage::AzureStore deleting '#{remote_path}'"
          blob_service.delete_blob(container.name, remote_path)
        end
      end

      def check_configuration
        required = %w(storage_account storage_access_key container_name)

        raise Error, <<-EOS if required.map { |name| send(name) }.any?(&:nil?)
          Configuration Error
          #{required.map { |name| "##{name}" }.join(", ")} are all required
        EOS
      end
    end
  end
end
