describe 'shared/attachment/_update.html.haml', type: :view do
  let(:champ) { build(:champ_piece_justificative, dossier: create(:dossier)) }
  let(:attached_file) { champ.piece_justificative_file }
  let(:user_can_destroy) { false }
  let(:template) { nil }

  subject do
    form_for(champ.dossier) do |form|
      view.render Attachment::EditComponent.new(form: form, attached_file: attached_file, user_can_destroy: true, direct_upload: true, template:)
    end
  end

  context 'when there is no attached file' do
    before do
      champ.piece_justificative_file = nil
    end

    it 'renders a form field for uploading a file' do
      expect(subject).to have_selector('input[type=file]:not(.hidden)')
    end
  end

  context 'when there is an attached file' do
    it 'renders a form field for uploading a file' do
      expect(subject).to have_selector('input[type=file]:not(.hidden)')
    end

    it 'does not renders a link to the unsaved file' do
      expect(subject).not_to have_content(attached_file.filename.to_s)
    end

    it 'does not render action buttons' do
      expect(subject).not_to have_link('Remplacer')
      expect(subject).not_to have_link('Supprimer')
    end

    context 'and the attachment has been saved' do
      before { champ.save! }

      it 'renders a link to the file' do
        expect(subject).to have_content(attached_file.filename.to_s)
      end

      it 'hides the form field by default' do
        expect(subject).to have_selector('input[type=file].hidden')
      end

      it 'shows the Delete button by default' do
        is_expected.to have_link('Supprimer')
      end
    end
  end

  context 'when the user cannot destroy the attachment' do
    subject do
      form_for(champ.dossier) do |form|
        render Attachment::EditComponent.new(form: form,
          attached_file: attached_file,
          user_can_destroy: user_can_destroy,
          direct_upload: true)
      end
    end

    it 'hides the Delete button' do
      is_expected.not_to have_link('Supprimer')
    end
  end

  context 'when champ has a template' do
    let(:profil) { :user }
    let(:template) { champ.type_de_champ.piece_justificative_template }

    before do
      allow_any_instance_of(ActionView::Base).to receive(:administrateur_signed_in?).and_return(profil == :administrateur)
    end

    it 'renders a link to template' do
      expect(subject).to have_link('le modèle suivant')
      expect(subject).not_to have_text("éphémère")
    end

    context 'as an administrator' do
      let(:profil) { :administrateur }
      it 'warn about ephemeral template url' do
        expect(subject).to have_link('le modèle suivant')
        expect(subject).to have_text("éphémère")
      end
    end
  end
end
