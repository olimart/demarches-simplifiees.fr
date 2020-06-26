class TmpDossiersMigrateRevisionsJob < ApplicationJob
  def perform(except)
    dossiers = Dossier.with_discarded.where(revision_id: nil)

    dossiers.where
      .not(id: except)
      .includes(procedure: [:draft_revision, :published_revision])
      .limit(2000)
      .find_each do |dossier|
        if dossier.procedure.present?
          dossier.revision = dossier.procedure.active_revision
          dossier.save!(validate: false)
        else
          except << dossier.id
        end
      end

    if dossiers.where.not(id: except).exists?
      TmpDossiersMigrateRevisionsJob.perform_later(except)
    end
  end
end
