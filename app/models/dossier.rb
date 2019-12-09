class Dossier < ApplicationRecord
  self.ignored_columns = ['json_latlngs']
  include DossierFilteringConcern

  enum state: {
    brouillon:       'brouillon',
    en_construction: 'en_construction',
    en_instruction:  'en_instruction',
    accepte:         'accepte',
    refuse:          'refuse',
    sans_suite:      'sans_suite'
  }

  EN_CONSTRUCTION_OU_INSTRUCTION = [states.fetch(:en_construction), states.fetch(:en_instruction)]
  TERMINE = [states.fetch(:accepte), states.fetch(:refuse), states.fetch(:sans_suite)]
  INSTRUCTION_COMMENCEE = TERMINE + [states.fetch(:en_instruction)]
  SOUMIS = EN_CONSTRUCTION_OU_INSTRUCTION + TERMINE

  TAILLE_MAX_ZIP = 50.megabytes

  has_one :etablissement, dependent: :destroy
  has_one :individual, dependent: :destroy
  has_one :attestation, dependent: :destroy

  has_one_attached :justificatif_motivation

  has_many :champs, -> { root.public_only.ordered }, inverse_of: :dossier, dependent: :destroy
  has_many :champs_private, -> { root.private_only.ordered }, class_name: 'Champ', inverse_of: :dossier, dependent: :destroy
  has_many :commentaires, inverse_of: :dossier, dependent: :destroy
  has_many :invites, dependent: :destroy
  has_many :follows, -> { active }, inverse_of: :dossier
  has_many :previous_follows, -> { inactive }, class_name: 'Follow', inverse_of: :dossier
  has_many :followers_instructeurs, through: :follows, source: :instructeur
  has_many :previous_followers_instructeurs, -> { distinct }, through: :previous_follows, source: :instructeur
  has_many :avis, inverse_of: :dossier, dependent: :destroy

  has_many :dossier_operation_logs, dependent: :destroy

  belongs_to :groupe_instructeur
  has_one :procedure, through: :groupe_instructeur
  belongs_to :user

  accepts_nested_attributes_for :champs
  accepts_nested_attributes_for :champs_private

  include AASM

  aasm whiny_persistence: true, column: :state, enum: true do
    state :brouillon, initial: true
    state :en_construction
    state :en_instruction
    state :accepte
    state :refuse
    state :sans_suite

    event :passer_en_construction, after: :after_passer_en_construction do
      transitions from: :brouillon, to: :en_construction
    end

    event :passer_en_instruction, after: :after_passer_en_instruction do
      transitions from: :en_construction, to: :en_instruction
    end

    event :passer_automatiquement_en_instruction, after: :after_passer_automatiquement_en_instruction do
      transitions from: :en_construction, to: :en_instruction
    end

    event :repasser_en_construction, after: :after_repasser_en_construction do
      transitions from: :en_instruction, to: :en_construction
    end

    event :accepter, after: :after_accepter do
      transitions from: :en_instruction, to: :accepte
    end

    event :accepter_automatiquement, after: :after_accepter_automatiquement do
      transitions from: :en_construction, to: :accepte
    end

    event :refuser, after: :after_refuser do
      transitions from: :en_instruction, to: :refuse
    end

    event :classer_sans_suite, after: :after_classer_sans_suite do
      transitions from: :en_instruction, to: :sans_suite
    end

    event :repasser_en_instruction, after: :after_repasser_en_instruction do
      transitions from: :refuse, to: :en_instruction
      transitions from: :sans_suite, to: :en_instruction
      transitions from: :accepte, to: :en_instruction
    end
  end

  default_scope { where(hidden_at: nil) }
  scope :state_brouillon,                      -> { where(state: states.fetch(:brouillon)) }
  scope :state_not_brouillon,                  -> { where.not(state: states.fetch(:brouillon)) }
  scope :state_en_construction,                -> { where(state: states.fetch(:en_construction)) }
  scope :state_en_instruction,                 -> { where(state: states.fetch(:en_instruction)) }
  scope :state_en_construction_ou_instruction, -> { where(state: EN_CONSTRUCTION_OU_INSTRUCTION) }
  scope :state_instruction_commencee,          -> { where(state: INSTRUCTION_COMMENCEE) }
  scope :state_termine,                        -> { where(state: TERMINE) }

  scope :archived,      -> { where(archived: true) }
  scope :not_archived,  -> { where(archived: false) }

  scope :order_by_updated_at, -> (order = :desc) { order(updated_at: order) }
  scope :order_by_created_at, -> (order = :asc) { order(en_construction_at: order, created_at: order, id: order) }
  scope :updated_since,       -> (since) { where('dossiers.updated_at >= ?', since) }
  scope :created_since,       -> (since) { where('dossiers.en_construction_at >= ?', since) }

  scope :all_state,                   -> { not_archived.state_not_brouillon }
  scope :en_construction,             -> { not_archived.state_en_construction }
  scope :en_instruction,              -> { not_archived.state_en_instruction }
  scope :termine,                     -> { not_archived.state_termine }
  scope :downloadable_sorted,         -> {
    state_not_brouillon
      .includes(
        :user,
        :individual,
        :followers_instructeurs,
        :avis,
        etablissement: :champ,
        champs: {
          etablissement: :champ,
          type_de_champ: :drop_down_list
        },
        champs_private: {
          etablissement: :champ,
          type_de_champ: :drop_down_list
        },
        procedure: :groupe_instructeurs
      ).order(en_construction_at: 'asc')
  }
  scope :en_cours,                    -> { not_archived.state_en_construction_ou_instruction }
  scope :without_followers,           -> { left_outer_joins(:follows).where(follows: { id: nil }) }
  scope :with_champs,                 -> { includes(champs: :type_de_champ) }
  scope :nearing_end_of_retention,    -> (duration = '1 month') { joins(:procedure).where("en_instruction_at + (duree_conservation_dossiers_dans_ds * interval '1 month') - now() < interval ?", duration) }
  scope :for_api, -> {
    includes(commentaires: { piece_jointe_attachment: :blob },
      champs: [
        :geo_areas,
        :etablissement,
        piece_justificative_file_attachment: :blob,
        champs: [
          piece_justificative_file_attachment: :blob
        ]
      ],
      champs_private: [
        :geo_areas,
        :etablissement,
        piece_justificative_file_attachment: :blob,
        champs: [
          piece_justificative_file_attachment: :blob
        ]
      ],
      justificatif_motivation_attachment: :blob,
      attestation: [],
      avis: { piece_justificative_file_attachment: :blob },
      etablissement: [],
      individual: [],
      user: [])
  }

  scope :for_procedure, -> (procedure) { includes(:user, :groupe_instructeur).where(groupe_instructeurs: { procedure: procedure }) }
  scope :for_api_v2, -> { includes(procedure: [:administrateurs], etablissement: [], individual: []) }

  scope :with_notifications, -> do
    # This scope is meant to be composed, typically with Instructeur.followed_dossiers, which means that the :follows table is already INNER JOINed;
    # it will fail otherwise
    joined_dossiers = joins('LEFT OUTER JOIN "champs" ON "champs" . "dossier_id" = "dossiers" . "id" AND "champs" . "parent_id" IS NULL AND "champs" . "private" = FALSE AND "champs"."updated_at" > "follows"."demande_seen_at"')
      .joins('LEFT OUTER JOIN "champs" "champs_privates_dossiers" ON "champs_privates_dossiers" . "dossier_id" = "dossiers" . "id" AND "champs_privates_dossiers" . "parent_id" IS NULL AND "champs_privates_dossiers" . "private" = TRUE AND "champs_privates_dossiers"."updated_at" > "follows"."annotations_privees_seen_at"')
      .joins('LEFT OUTER JOIN "avis" ON "avis" . "dossier_id" = "dossiers" . "id" AND avis.updated_at > follows.avis_seen_at')
      .joins('LEFT OUTER JOIN "commentaires" ON "commentaires" . "dossier_id" = "dossiers" . "id" and commentaires.updated_at > follows.messagerie_seen_at and "commentaires"."email" != \'contact@tps.apientreprise.fr\' AND "commentaires"."email" != \'mes-demarches@modernisation.gov.pf\'')

    updated_demandes = joined_dossiers
      .where('champs.updated_at > follows.demande_seen_at')

    updated_annotations = joined_dossiers
      .where('champs_privates_dossiers.updated_at > follows.annotations_privees_seen_at')

    updated_avis = joined_dossiers
      .where('avis.updated_at > follows.avis_seen_at')

    updated_messagerie = joined_dossiers
      .where('commentaires.updated_at > follows.messagerie_seen_at')
      .where.not(commentaires: { email: OLD_CONTACT_EMAIL })
      .where.not(commentaires: { email: CONTACT_EMAIL })

    updated_demandes.or(updated_annotations).or(updated_avis).or(updated_messagerie).distinct
  end

  accepts_nested_attributes_for :individual

  delegate :siret, :siren, to: :etablissement, allow_nil: true
  delegate :types_de_champ, to: :procedure
  delegate :france_connect_information, to: :user

  before_validation :update_state_dates, if: -> { state_changed? }

  before_save :build_default_champs, if: Proc.new { groupe_instructeur_id_was.nil? }
  before_save :build_default_individual, if: Proc.new { procedure.for_individual? }
  before_save :update_search_terms

  after_save :send_dossier_received
  after_save :send_web_hook
  after_create :send_draft_notification_email

  validates :user, presence: true

  def update_search_terms
    self.search_terms = [
      user&.email,
      *champs.flat_map(&:search_terms),
      *etablissement&.search_terms,
      individual&.nom,
      individual&.prenom
    ].compact.join(' ')
    self.private_search_terms = champs_private.flat_map(&:search_terms).compact.join(' ')
  end

  def build_default_champs
    procedure.build_champs.each do |champ|
      champs << champ
    end
    procedure.build_champs_private.each do |champ|
      champs_private << champ
    end
  end

  def build_default_individual
    if Individual.where(dossier_id: self.id).count == 0
      build_individual
    end
  end

  def en_construction_ou_instruction?
    EN_CONSTRUCTION_OU_INSTRUCTION.include?(state)
  end

  def termine?
    TERMINE.include?(state)
  end

  def instruction_commencee?
    INSTRUCTION_COMMENCEE.include?(state)
  end

  def reset!
    etablissement.destroy

    update_columns(autorisation_donnees: false)
  end

  def read_only?
    en_instruction? || accepte? || refuse? || sans_suite?
  end

  def can_transition_to_en_construction?
    !procedure.close? && brouillon?
  end

  def can_be_updated_by_user?
    brouillon? || en_construction?
  end

  def can_be_deleted_by_user?
    brouillon? || en_construction?
  end

  def messagerie_available?
    !brouillon? && !archived
  end

  def retention_end_date
    if instruction_commencee?
      en_instruction_at + procedure.duree_conservation_dossiers_dans_ds.months
    end
  end

  def retention_expired?
    instruction_commencee? && retention_end_date <= Time.zone.now
  end

  def text_summary
    if brouillon?
      parts = [
        "Dossier en brouillon répondant à la démarche ",
        procedure.libelle,
        " gérée par l'organisme ",
        procedure.organisation_name
      ]
    else
      parts = [
        "Dossier déposé le ",
        en_construction_at.strftime("%d/%m/%Y"),
        " sur la démarche ",
        procedure.libelle,
        " gérée par l'organisme ",
        procedure.organisation_name
      ]
    end

    parts.join
  end

  def avis_for(instructeur)
    if instructeur.dossiers.include?(self)
      avis.order(created_at: :asc)
    else
      avis
        .where(confidentiel: false)
        .or(avis.where(claimant: instructeur))
        .or(avis.where(instructeur: instructeur))
        .order(created_at: :asc)
    end
  end

  def owner_name
    if etablissement.present?
      etablissement.entreprise_raison_sociale
    elsif individual.present?
      "#{individual.nom} #{individual.prenom}"
    end
  end

  def expose_legacy_carto_api?
    procedure.expose_legacy_carto_api?
  end

  def geo_position
    if etablissement.present?
      point = ApiAdresse::PointAdapter.new(etablissement.geo_adresse).geocode
    end

    lon = "2.428462"
    lat = "46.538192"
    zoom = "13"

    if point.present?
      lon = point.x.to_s
      lat = point.y.to_s
    end

    { lon: lon, lat: lat, zoom: zoom }
  end

  def unspecified_attestation_champs
    attestation_template = procedure.attestation_template

    if attestation_template&.activated?
      attestation_template.unspecified_champs_for_dossier(self)
    else
      []
    end
  end

  def build_attestation
    if procedure.attestation_template&.activated?
      procedure.attestation_template.attestation_for(self)
    end
  end

  def delete_and_keep_track(author)
    deleted_dossier = DeletedDossier.create_from_dossier(self)
    update(hidden_at: deleted_dossier.deleted_at)

    if en_construction?
      administration_emails = followers_instructeurs.present? ? followers_instructeurs.map(&:email) : procedure.administrateurs.pluck(:email)
      administration_emails.each do |email|
        DossierMailer.notify_deletion_to_administration(deleted_dossier, email).deliver_later
      end
    end
    DossierMailer.notify_deletion_to_user(deleted_dossier, user.email).deliver_later

    log_dossier_operation(author, :supprimer, self)
  end

  def after_passer_en_instruction(instructeur)
    instructeur.follow(self)

    log_dossier_operation(instructeur, :passer_en_instruction)
  end

  def after_passer_automatiquement_en_instruction
    log_automatic_dossier_operation(:passer_en_instruction)
  end

  def after_repasser_en_construction(instructeur)
    self.en_instruction_at = nil

    save!
    log_dossier_operation(instructeur, :repasser_en_construction)
  end

  def after_repasser_en_instruction(instructeur)
    self.processed_at = nil
    self.motivation = nil
    attestation&.destroy

    save!
    DossierMailer.notify_revert_to_instruction(self).deliver_later
    log_dossier_operation(instructeur, :repasser_en_instruction)
  end

  def after_accepter(instructeur, motivation, justificatif = nil)
    self.motivation = motivation

    if justificatif
      self.justificatif_motivation.attach(justificatif)
    end

    if attestation.nil?
      self.attestation = build_attestation
    end

    save!
    NotificationMailer.send_closed_notification(self).deliver_later
    log_dossier_operation(instructeur, :accepter, self)
  end

  def after_accepter_automatiquement
    self.en_instruction_at ||= Time.zone.now

    if attestation.nil?
      self.attestation = build_attestation
    end

    save!
    NotificationMailer.send_closed_notification(self).deliver_later
    log_automatic_dossier_operation(:accepter, self)
  end

  def after_refuser(instructeur, motivation, justificatif = nil)
    self.motivation = motivation

    if justificatif
      self.justificatif_motivation.attach(justificatif)
    end

    save!
    NotificationMailer.send_refused_notification(self).deliver_later
    log_dossier_operation(instructeur, :refuser, self)
  end

  def after_classer_sans_suite(instructeur, motivation, justificatif = nil)
    self.motivation = motivation

    if justificatif
      self.justificatif_motivation.attach(justificatif)
    end

    save!
    NotificationMailer.send_without_continuation_notification(self).deliver_later
    log_dossier_operation(instructeur, :classer_sans_suite, self)
  end

  def check_mandatory_champs
    (champs + champs.filter(&:repetition?).flat_map(&:champs))
      .filter(&:mandatory_and_blank?)
      .map do |champ|
        "Le champ #{champ.libelle.truncate(200)} doit être rempli."
      end
  end

  def match_encoded_date?(field, encoded_date)
    datetime = send(field)
    if (match = encoded_date.match(/([0-9a-f]{8})-([0-9a-f]{0,8})/))
      seconds, nseconds = match.captures.map { |x| x.to_i(16) }
      seconds == datetime.to_i && nseconds == datetime.nsec
    else
      false
    end
  end

  def encoded_date(field)
    datetime = send(field)
    datetime.to_i.to_s(16) + '-' + datetime.nsec.to_s(16)
  end

  def modifier_annotations!(instructeur)
    champs_private.filter(&:value_previously_changed?).each do |champ|
      log_dossier_operation(instructeur, :modifier_annotation, champ)
    end
  end

  def demander_un_avis!(avis)
    log_dossier_operation(avis.claimant, :demander_un_avis, avis)
  end

  def spreadsheet_columns_csv
    spreadsheet_columns(with_etablissement: true)
  end

  def spreadsheet_columns_xlsx
    spreadsheet_columns
  end

  def spreadsheet_columns_ods
    spreadsheet_columns
  end

  def spreadsheet_columns(with_etablissement: false)
    columns = [
      ['ID', id.to_s],
      ['Email', user.email]
    ]

    if procedure.for_individual?
      columns += [
        ['Civilité', individual&.gender],
        ['Nom', individual&.nom],
        ['Prénom', individual&.prenom],
        ['Date de naissance', individual&.birthdate]
      ]
    elsif with_etablissement
      columns += [
        ['Établissement SIRET', etablissement&.siret],
        ['Établissement siège social', etablissement&.siege_social],
        ['Établissement NAF', etablissement&.naf],
        ['Établissement libellé NAF', etablissement&.libelle_naf],
        ['Établissement Adresse', etablissement&.adresse],
        ['Établissement numero voie', etablissement&.numero_voie],
        ['Établissement type voie', etablissement&.type_voie],
        ['Établissement nom voie', etablissement&.nom_voie],
        ['Établissement complément adresse', etablissement&.complement_adresse],
        ['Établissement code postal', etablissement&.code_postal],
        ['Établissement localité', etablissement&.localite],
        ['Établissement code INSEE localité', etablissement&.code_insee_localite],
        ['Entreprise SIREN', etablissement&.entreprise_siren],
        ['Entreprise capital social', etablissement&.entreprise_capital_social],
        ['Entreprise numero TVA intracommunautaire', etablissement&.entreprise_numero_tva_intracommunautaire],
        ['Entreprise forme juridique', etablissement&.entreprise_forme_juridique],
        ['Entreprise forme juridique code', etablissement&.entreprise_forme_juridique_code],
        ['Entreprise nom commercial', etablissement&.entreprise_nom_commercial],
        ['Entreprise raison sociale', etablissement&.entreprise_raison_sociale],
        ['Entreprise SIRET siège social', etablissement&.entreprise_siret_siege_social],
        ['Entreprise code effectif entreprise', etablissement&.entreprise_code_effectif_entreprise],
        ['Entreprise date de création', etablissement&.entreprise_date_creation],
        ['Entreprise nom', etablissement&.entreprise_nom],
        ['Entreprise prénom', etablissement&.entreprise_prenom],
        ['Association RNA', etablissement&.association_rna],
        ['Association titre', etablissement&.association_titre],
        ['Association objet', etablissement&.association_objet],
        ['Association date de création', etablissement&.association_date_creation],
        ['Association date de déclaration', etablissement&.association_date_declaration],
        ['Association date de publication', etablissement&.association_date_publication]
      ]
    else
      columns << ['Entreprise raison sociale', etablissement&.entreprise_raison_sociale]
    end

    columns += [
      ['Archivé', :archived],
      ['État du dossier', I18n.t(state, scope: [:activerecord, :attributes, :dossier, :state])],
      ['Dernière mise à jour le', :updated_at],
      ['Déposé le', :en_construction_at],
      ['Passé en instruction le', :en_instruction_at],
      ['Traité le', :processed_at],
      ['Motivation de la décision', :motivation],
      ['Instructeurs', followers_instructeurs.map(&:email).join(' ')]
    ]

    if procedure.routee?
      columns << ['Groupe instructeur', groupe_instructeur.label]
    end

    columns + champs_for_export + annotations_for_export
  end

  def champs_for_export
    champs.reject(&:exclude_from_export?).map do |champ|
      [champ.libelle, champ.for_export]
    end
  end

  def annotations_for_export
    champs_private.reject(&:exclude_from_export?).map do |champ|
      [champ.libelle, champ.for_export]
    end
  end

  def attachments_downloadable?
    !PiecesJustificativesService.liste_pieces_justificatives(self).empty? && PiecesJustificativesService.pieces_justificatives_total_size(self) < Dossier::TAILLE_MAX_ZIP
  end

  def update_with_france_connect(fc_information)
    self.individual = Individual.create_from_france_connect(fc_information)
  end

  def linked_dossiers
    Dossier.where(id: champs.filter(&:dossier_link?).map(&:value).compact)
  end

  private

  def log_dossier_operation(author, operation, subject = nil)
    DossierOperationLog.create_and_serialize(
      dossier: self,
      operation: DossierOperationLog.operations.fetch(operation),
      author: author,
      subject: subject
    )
  end

  def log_automatic_dossier_operation(operation, subject = nil)
    DossierOperationLog.create_and_serialize(
      dossier: self,
      operation: DossierOperationLog.operations.fetch(operation),
      automatic_operation: true,
      subject: subject
    )
  end

  def update_state_dates
    if en_construction? && !self.en_construction_at
      self.en_construction_at = Time.zone.now
    elsif en_instruction? && !self.en_instruction_at
      self.en_instruction_at = Time.zone.now
    elsif TERMINE.include?(state)
      self.processed_at = Time.zone.now
    end
  end

  def send_dossier_received
    if saved_change_to_state? && en_instruction? && !procedure.declarative_accepte?
      NotificationMailer.send_dossier_received(self).deliver_later
    end
  end

  def send_draft_notification_email
    if brouillon? && !procedure.declarative?
      DossierMailer.notify_new_draft(self).deliver_later
    end
  end

  def send_web_hook
    if saved_change_to_state? && !brouillon? && procedure.web_hook_url
      WebHookJob.perform_later(
        procedure,
        self
      )
    end
  end
end
