RSpec.describe GeoArea, type: :model do
  describe '#area' do
    let(:geo_area) { build(:geo_area, :polygon) }

    it { expect(geo_area.area).to eq(103.6) }
  end

  describe '#area (hourglass polygon)' do
    let(:geo_area) { build(:geo_area, :hourglass_polygon) }

    it { expect(geo_area.area).to eq(32.4) }
  end

  describe '#length' do
    let(:geo_area) { build(:geo_area, :line_string) }

    it { expect(geo_area.length).to eq(30.8) }
  end

  describe '#location' do
    let(:geo_area) { build(:geo_area, :point) }

    it { expect(geo_area.location).to eq("46°32'19\"N 2°25'42\"E") }
  end

  describe '#rgeo_geometry' do
    let(:geo_area) { build(:geo_area, geometry: geometry) }

    context 'invalid' do
      let(:geometry) do
        {
          "type" => "MultiPolygon",
          "coordinates" => [
            [
              [
                [5.894422531127931, 48.22810341752755],
                [5.893049240112306, 48.22427237832278],
                [5.892534255981446, 48.22593062452037],
                [5.892791748046875, 48.2260449843468],
                [5.894422531127931, 48.229933066408215],
                [5.894422531127931, 48.22810341752755]
              ]
            ],
            [
              [
                [5.8950233459472665, 48.229933066408215],
                [5.893478393554688, 48.228961073585126],
                [5.892791748046875, 48.228903896961775],
                [5.892705917358398, 48.230390468407535],
                [5.8950233459472665, 48.229933066408215]
              ]
            ],
            [
              [
                [5.893220901489259, 48.229246955743626],
                [5.893392562866212, 48.22884672027457],
                [5.892705917358398, 48.22878954352343],
                [5.892019271850587, 48.22856083588024],
                [5.892019271850587, 48.2277031731152],
                [5.890989303588868, 48.22787470681807],
                [5.889959335327149, 48.22787470681807],
                [5.890560150146485, 48.22838930447709],
                [5.890645980834962, 48.22878954352343],
                [5.890989303588868, 48.229018250144584],
                [5.892362594604493, 48.22930413198368],
                [5.893220901489259, 48.229246955743626]
              ]
            ]
          ]
        }
      end

      it { expect(geo_area.rgeo_geometry).to be_nil }
    end
  end
end
