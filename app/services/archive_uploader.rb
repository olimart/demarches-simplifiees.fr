class ArchiveUploader
  # see: https://docs.ovh.com/fr/storage/pcs/capabilities-and-limitations/#max_file_size-5368709122-5gb
  # officialy it's 5Gb. but let's avoid to reach the exact spot of the limit
  # when file size is bigger, active storage expects the chunks + a manifest.
  MAX_FILE_SIZE_FOR_BACKEND_BEFORE_CHUNKING = ENV.fetch('ACTIVE_STORAGE_FILE_SIZE_THRESHOLD_BEFORE_CUSTOM_UPLOAD') { 4.gigabytes }.to_i

  def upload
    uploaded_blob = create_and_upload_blob
    begin
      archive.file.purge if archive.file.attached?
    rescue ActiveStorage::FileNotFoundError
      archive.file.destroy
      archive.file.detach
    end
    archive.reload
    ActiveStorage::Attachment.create(
      name: 'file',
      record_type: 'Archive',
      record_id: archive.id,
      blob_id: uploaded_blob.id
    )
  end

  private

  attr_reader :procedure, :archive, :filepath

  def create_and_upload_blob
    if active_storage_service_local? || File.size(filepath) < MAX_FILE_SIZE_FOR_BACKEND_BEFORE_CHUNKING
      upload_with_active_storage
    else
      upload_with_chunking_wrapper
    end
  end

  def active_storage_service_local?
    Rails.application.config.active_storage.service == :local
  end

  def upload_with_active_storage
    params = blob_default_params(filepath).merge(io: File.open(filepath),
                                                 identify: false)
    blob = ActiveStorage::Blob.create_and_upload!(**params)
    return blob
  end

  def upload_with_chunking_wrapper
    params =  blob_default_params(filepath).merge(byte_size: File.size(filepath),
                                                  checksum: Digest::SHA256.file(filepath).hexdigest)
    blob = ActiveStorage::Blob.create_before_direct_upload!(**params)
    if syscall_to_custom_uploader(blob)
      return blob
    else
      blob.purge
      fail "custom archive attachment failed, should it be retried ?"
    end
  end

  # keeps consistency between ActiveStorage api calls (otherwise archives are not storaged in '/archives') :
  # - create_and_upload, blob is attached by active storage
  # - upload_with_chunking_wrapper, blob is attached by custom script
  def blob_default_params(filepath)
    {
      key: namespaced_object_key,
      filename: archive.filename(procedure),
      content_type: 'application/zip',
      metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
    }
  end

  # explicitely memoize so it keeps its consistency across many calls (Ex: retry)
  def namespaced_object_key
    @namespaced_object_key ||= "archives/#{Date.today.strftime("%Y-%m-%d")}/#{SecureRandom.uuid}"
  end

  def syscall_to_custom_uploader(blob)
    system(ENV.fetch('ACTIVE_STORAGE_BIG_FILE_UPLOADER_WITH_ENCRYPTION_PATH').to_s, filepath, blob.key, exception: true)
  end

  def initialize(procedure:, archive:, filepath:)
    @procedure = procedure
    @archive = archive
    @filepath = filepath
  end
end