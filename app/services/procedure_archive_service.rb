require 'tempfile'

class ProcedureArchiveService
  def initialize(procedure)
    @procedure = procedure
  end

  def create_pending_archive(instructeur, type, month = nil)
    groupe_instructeurs = instructeur
      .groupe_instructeurs
      .where(procedure: @procedure)

    Archive.find_or_create_archive(type, month, groupe_instructeurs)
  end

  def make_and_upload_archive(archive, instructeur)
    dossiers = Dossier.visible_by_administration
      .where(groupe_instructeur: archive.groupe_instructeurs)

    dossiers = if archive.time_span_type == 'everything'
      dossiers.state_termine
    else
      dossiers.processed_in_month(archive.month)
    end

    attachments = ActiveStorage::DownloadableFile.create_list_from_dossiers(dossiers)

      ArchiveUploader.new(procedure: @procedure, archive: archive, filepath: zip_filepath)
        .upload
    DownloadableFileService.download_and_zip(@procedure, attachments, zip_root_folder(archive)) do |zip_filepath|
    end
  end

  def self.procedure_files_size(procedure)
    dossiers_files_size(procedure.dossiers)
  end

  def self.dossiers_files_size(dossiers)
    dossiers.map do |dossier|
      liste_pieces_justificatives_for_archive(dossier).sum(&:byte_size)
    end.sum
  end

  private

  def zip_root_folder(archive)
    "procedure-#{@procedure.id}-#{archive.id}"
  end

  def self.attachments_from_champs_piece_justificative(champs)
    champs
      .filter { |c| c.type_champ == TypeDeChamp.type_champs.fetch(:piece_justificative) }
      .map(&:piece_justificative_file)
      .filter(&:attached?)
  end

  def self.liste_pieces_justificatives_for_archive(dossier)
    champs_blocs_repetables = dossier.champs
      .filter { |c| c.type_champ == TypeDeChamp.type_champs.fetch(:repetition) }
      .flat_map(&:champs)

    attachments_from_champs_piece_justificative(champs_blocs_repetables + dossier.champs)
  end
end
